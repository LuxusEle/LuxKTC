# frozen_string_literal: true
# Local SketchUp HtmlDialog. All shared-data I/O goes through the Ruby bridge.
require_relative 'sync' unless defined?(AJBoardKitchen::Sync)
require 'json'
require 'digest'

module AJBoardKitchen
  module Studio
    extend self
    remove_const(:ACTIONS) if const_defined?(:ACTIONS, false)
    ACTIONS = %w[ready list poll create open apply save pull delete_project report toggle open_web capture].freeze
    POSITION_KEYS = %i[x_mm y_mm z_mm rotation_deg].freeze unless const_defined?(:POSITION_KEYS)
    # A development reload must not leave a replaced dialog waiting on an old
    # callback, nor let that callback replace a newer editor's state.
    @operation = (@operation || 0) + 1
    @busy = false
    @ready = false
    @report = nil

    def show
      if @dialog
        @dialog.bring_to_front
        emit
        return @dialog
      end
      @ready = false
      @dialog = UI::HtmlDialog.new(dialog_title: 'LuxKTC Project Studio', preferences_key: 'LuxKTC.ProjectStudio',
        scrollable: true, resizable: true, width: 1180, height: 820, min_width: 780, min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.add_action_callback('luxktc_action') { |_context, body| handle(body) }
      created = @dialog
      @dialog.set_on_closed do
        if @dialog.equal?(created)
          @dialog = nil; @ready = false; @busy = false
          @operation = (@operation || 0) + 1
          Sync.instance_variable_set(:@pull_serial, Sync.instance_variable_get(:@pull_serial).to_i + 1)
        end
      end
      @dialog.set_file(File.join(AJBoardKitchen::ROOT, 'studio.html'))
      @dialog.show
      @dialog
    end

    def active_project
      Sync.active? ? Sync.project : nil
    end
    def model_serial
      Sync.instance_variable_get(:@change_serial).to_i
    end
    def fallback_catalog
      cabinets = ProjectBridge::TYPES.reject { |type| type == 'base_hob' }.map do |type|
        row = AJBoardScaffold.catalogue.find { |entry| entry[:id] == type }
        {type: type, name: type == 'tall_oven_micro' ? 'Tall / two ovens and drawers' : row[:name],
          width_mm: row[:w], height_mm: type.start_with?('wall_') ? 600 : row[:h], depth_mm: row[:d]}
      end
      {cabinets: cabinets, connectors: %w[minifix screw minifix_dowel rafix ovvo_od830 dowel],
        hinges: %w[cup35_screw cup35_dowel none]}
    end
    def report_key(project)
      Digest::SHA256.hexdigest(JSON.generate(project.slice(:id, :room, :design, :quote)))
    end
    def visibility
      return {} unless Sync.active?
      AJBoardKitchen::CATEGORIES.to_h do |category|
        layer = Sketchup.active_model.layers["AJ Board / #{category}"]
        [category, layer ? layer.visible? : true]
      end
    end
    def snapshot(accept_draft: false, **extra)
      project = active_project
      report = project && @report && @report[:key] == report_key(project) ? @report : {}
      {project: project, projects: @projects || [], catalog: @catalog || fallback_catalog,
        bom: report[:bom], quote: report[:quote], server: Sync.server,
        busy: !!@busy, dirty: !!(project && Sync.instance_variable_get(:@dirty)), model_serial: model_serial,
        remote_revision: @remote_revision, message: @message || 'Ready. Wall photographs are optional.',
        error: @error, visibility: visibility, accept_draft: accept_draft}.merge(extra)
    end
    def emit(accept_draft: false, **extra)
      return unless @dialog && @ready
      json = JSON.generate(snapshot(accept_draft: accept_draft, **extra)).gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      @dialog.execute_script("window.LuxKTCStudio && window.LuxKTCStudio.receive(#{json});")
    end
    def sync_changed
      # This notification must not start a network request or replace a form.
      emit
    end

    def begin_operation(message)
      @busy = true; @error = nil; @message = message
      @operation = (@operation || 0) + 1
      @operation_model = Sketchup.active_model
      @operation_project = active_project&.dig(:id)
      emit
      @operation
    end
    def current_operation?(token, allow_project_change: false)
      return false unless @operation == token
      unless Sketchup.active_model.equal?(@operation_model)
        finish_error(token, 'The active SketchUp model changed. The response was not applied to this model.')
        return false
      end
      if !allow_project_change && active_project&.dig(:id) != @operation_project
        finish_error(token, 'The active project changed. Refresh the studio before continuing.')
        return false
      end
      true
    end
    def finish(token, message, accept_draft: false, **extra)
      return unless @operation == token
      @busy = false; @error = nil; @message = message
      emit(accept_draft: accept_draft, **extra)
    end
    def finish_error(token, message, status = 0, data = {})
      return unless @operation == token
      @busy = false
      if data.is_a?(Hash) && data[:cancelled]
        @error = nil; @message = message
      else
        @error = message.to_s; @message = 'Your local edits are retained.'
        @remote_revision = data[:current_revision] if status == 409 && data.is_a?(Hash)
      end
      emit
    end
    def failure(token)
      proc { |message, status, data| finish_error(token, message, status, data) }
    end
    def http(token, method, path, body = nil, allow_project_change: false, &done)
      Sync.request(method, path, body, on_error: failure(token)) do |data, response|
        next unless current_operation?(token, allow_project_change: allow_project_change)
        done.call(data, response)
      end
    end

    def handle(body)
      if @busy
        emit
        return
      end
      input = body.is_a?(Hash) ? ProjectBridge.copy(body) : JSON.parse(body.to_s, symbolize_names: true)
      raise ArgumentError, 'Invalid studio action.' unless input.is_a?(Hash) && ACTIONS.include?(input[:action])
      payload = input[:payload] || {}
      raise ArgumentError, 'Invalid studio input.' unless payload.is_a?(Hash)
      action = input[:action]
      @ready = true if action == 'ready'
      token = begin_operation('Working...')
      case action
      when 'ready', 'list'
        emit(accept_draft: action == 'ready')
        refresh_list(token, initial: action == 'ready')
      when 'poll'
        http(token, :get, '/api/projects') do |rows, _response|
          @projects = rows
          remote = active_project && rows.find { |row| row[:id] == active_project[:id] }
          @remote_revision = remote && remote[:revision] > active_project[:revision] ? remote[:revision] : nil
          finish(token, @remote_revision ? "Web revision #{@remote_revision} is available. Pull web changes when ready." : 'No newer shared revision found.')
        end
      when 'create'
        http(token, :post, '/api/projects', {name: payload.fetch(:name, 'Kitchen project'),
          client: payload.fetch(:client, ''), template: payload.fetch(:template, 'empty')}) do |created, _response|
          @projects ||= []
          @projects.unshift(created.slice(:id, :name, :client, :revision, :updated_at))
          open_project(token, created.fetch(:id))
        end
      when 'open'
        open_project(token, payload.fetch(:id))
      when 'pull'
        raise 'Open or create a project in the studio first.' unless active_project
        open_project(token, active_project[:id])
      when 'apply'
        candidate = prepare_project(payload)
        Sync.apply_project(candidate, dirty: true, preserve_camera: true)
        @report = nil
        @retry_serial = nil
        finish(token, 'Model built locally. Save to web to update the shared project.', accept_draft: true)
      when 'save'
        candidate = prepare_project(payload)
        Sync.apply_project(candidate, dirty: true, preserve_camera: true)
        @report = nil
        submitted_serial = payload[:base_model_serial]
        save_failure = proc do |message, status, data|
          # A failed save already built this exact draft locally. Permit a
          # corrected retry from that same form, unless a separate model edit
          # has since changed the project's parametric data.
          if @operation == token && active_project && form_key(active_project) == form_key(candidate)
            @retry_serial = {source: submitted_serial, current: model_serial, id: candidate[:id]}
          end
          finish_error(token, message, status, data)
        end
        Sync.push(on_error: save_failure, on_success: proc do |saved|
          next unless current_operation?(token)
          @retry_serial = nil
          @remote_revision = nil
          remember_summary(saved)
          finish(token, "Saved shared revision #{saved[:revision]}.", accept_draft: true)
        end)
      when 'capture'
        capture_model
        @report = nil
        finish(token, 'Supported model placements read into the studio.', accept_draft: true)
      when 'report'
        candidate = prepare_project(payload)
        generated = ProjectBridge.generate(candidate)
        http(token, :post, '/api/preview', {project: candidate, generated: generated}) do |result, _response|
          @report = {key: report_key(candidate), bom: result[:bom], quote: result[:quote]}
          finish(token, 'Local BOM and quote preview. This action did not save the web project.',
            bom: result[:bom], quote: result[:quote], accept_draft: false)
        end
      when 'delete_project'
        delete_project(token)
      when 'toggle'
        category = payload.fetch(:category)
        raise ArgumentError, 'Unknown visibility category.' unless AJBoardKitchen::CATEGORIES.include?(category)
        AJBoardKitchen.toggle(category)
        finish(token, "#{category} visibility changed.")
      when 'open_web'
        url = Sync.server
        url += "/?project=#{Sync.safe_id(active_project[:id])}" if active_project
        UI.openURL(url)
        finish(token, 'Web interface opened.')
      end
    rescue StandardError => error
      if token
        finish_error(token, error.message)
      else
        @error = error.message; emit
      end
    end

    def refresh_list(token, initial: false)
      http(token, :get, '/api/projects') do |rows, _response|
        @projects = rows
        http(token, :get, '/api/catalog') do |catalog, _catalog_response|
          @catalog = catalog
          finish(token, initial ? 'Project studio ready. Create/open a project; wall photos are optional.' : 'Shared project list refreshed.')
        end
      end
    end
    def open_project(token, id)
      Sync.pull(Sync.safe_id(id), on_error: failure(token), on_success: proc do |project|
        next unless current_operation?(token, allow_project_change: true)
        @report = nil; @remote_revision = nil
        remember_summary(project)
        finish(token, "Opened #{project[:name]} at revision #{project[:revision]}.", accept_draft: true)
      end)
    end
    def remember_summary(project)
      @projects ||= []
      @projects.reject! { |row| row[:id] == project[:id] }
      @projects.unshift(project.slice(:id, :name, :client, :revision, :updated_at))
    end
    def form_key(project)
      JSON.generate(project.slice(:id, :name, :client, :room, :design, :quote))
    end
    def capture_model
      raise 'Open or create a project in the studio first.' unless active_project
      current = active_project
      observed = Sync.capture_positions(ProjectBridge.copy(current))
      if observed != current
        Sync.instance_variable_set(:@project, observed)
        Sync.instance_variable_set(:@dirty, true)
        Sync.instance_variable_set(:@change_serial, model_serial + 1)
        Sync.persist
      end
      observed
    end
    def same_value?(a, b)
      a.is_a?(Numeric) && b.is_a?(Numeric) ? (a - b).abs < 0.000001 : a == b
    end
    def prepare_project(payload)
      raise 'Open or create a project in the studio first.' unless active_project
      current = active_project
      candidate = ProjectBridge.copy(payload.fetch(:project))
      raise ArgumentError, 'Project input must be an object.' unless candidate.is_a?(Hash)
      raise 'The studio project changed. Refresh it before applying these edits.' unless candidate[:id] == current[:id] && candidate[:revision] == current[:revision]
      retry_allowed = @retry_serial && @retry_serial[:id] == current[:id] &&
        @retry_serial[:source] == payload[:base_model_serial] && @retry_serial[:current] == model_serial
      if payload.key?(:base_model_serial) && payload[:base_model_serial] != model_serial && !retry_allowed
        raise 'This form predates another SketchUp edit. Read model changes before applying it; your form is retained.'
      end
      # Capture supported native moves without discarding unrelated form edits.
      # Simultaneously editing the same position in both places is a conflict.
      observed = Sync.capture_positions(ProjectBridge.copy(current))
      current[:design][:cabinets].each do |before|
        moved = observed[:design][:cabinets].find { |row| row[:id] == before[:id] }
        changed = POSITION_KEYS.select { |key| !same_value?(moved[key], before[key]) }
        next if changed.empty?
        target = candidate.fetch(:design).fetch(:cabinets).find { |row| row[:id] == before[:id] }
        raise "#{before[:local_id]} moved in the model while you removed it in the studio. Read model changes first." unless target
        changed.each do |key|
          unless same_value?(target[key], before[key]) || same_value?(target[key], moved[key])
            raise "#{before[:local_id]} has two different #{key} edits. Read model changes before applying the form."
          end
          target[key] = moved[key]
        end
      end
      candidate[:manufacturing] = ProjectBridge.copy(current[:manufacturing] || {})
      # Invalidate old texture dimensions before building, just as the shared
      # store does, rather than waiting for another pull to remove them.
      candidate.fetch(:room).fetch(:walls).each do |wall|
        old = current[:room][:walls].find { |row| row[:id] == wall[:id] }
        changed = old && %i[width_mm height_mm photo_asset_id photo_quad].any? { |key| wall[key] != old[key] }
        rect = wall[:rectification]
        matches = rect.is_a?(Hash) && %i[width_mm height_mm].all? { |key| rect[key] == wall[key] } &&
          rect[:source_asset_id] == wall[:photo_asset_id] && rect[:quad] == wall[:photo_quad]
        if (changed || wall[:rectified_asset_id]) && !matches
          %i[rectified_asset_id annotated_asset_id rectification].each { |key| wall[key] = nil }
        end
      end
      candidate
    end
    def delete_project(token)
      raise 'Open a shared project before deleting it.' unless active_project
      project = ProjectBridge.copy(active_project)
      root = Sync.instance_variable_get(:@root)
      checkpoint = [root.transformation.to_a, Sync.geometry_signature(root)]
      http(token, :delete, "/api/projects/#{Sync.safe_id(project[:id])}?base_revision=#{Integer(project[:revision])}") do |_data, _response|
        if root.valid? && root == Sync.instance_variable_get(:@root)
          unchanged = checkpoint == [root.transformation.to_a, Sync.geometry_signature(root)]
          if unchanged
            model = Sketchup.active_model
            started = false
            begin
              model.start_operation('Delete LuxKTC project', true); started = true
              root.erase!
              model.commit_operation; started = false
            rescue StandardError
              model.abort_operation if started
              raise
            end
          else
            # A newer native edit is retained as local geometry, not erased by
            # completion of an older database request.
            root.delete_attribute(Sync::DICT, 'project')
            root.set_attribute(Sync::DICT, 'deleted_on_server', true)
          end
        end
        Sync.instance_variable_set(:@project, nil)
        Sync.instance_variable_set(:@root, nil)
        Sync.instance_variable_set(:@dirty, false)
        Sync.instance_variable_set(:@change_serial, model_serial + 1)
        AJBoardKitchen.instance_variable_set(:@view, nil)
        AJBoardKitchen.instance_variable_set(:@job, nil)
        @projects = (@projects || []).reject { |row| row[:id] == project[:id] }
        @report = nil
        finish(token, 'Shared project deleted. Any newer model edits were retained as local geometry.', accept_draft: true)
      end
    end
  end
end
