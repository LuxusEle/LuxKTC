# frozen_string_literal: true
require_relative 'project_bridge'
require 'uri'
require 'tmpdir'
require 'fileutils'

module AJBoardKitchen
  module Sync
    extend self
    DICT = 'LuxKTC' unless const_defined?(:DICT)
    DEFAULT_SERVER = 'http://127.0.0.1:8740' unless const_defined?(:DEFAULT_SERVER)
    class UnsupportedEdit < StandardError; end

    def server
      @server ||= Sketchup.read_default('LuxKTC', 'server', DEFAULT_SERVER)
      checked_server(@server)
    end
    def checked_server(value)
      uri = URI(value.to_s)
      raise ArgumentError, 'This development bridge accepts http://127.0.0.1:PORT only.' unless uri.scheme == 'http' && uri.host == '127.0.0.1' && !uri.userinfo && ['', '/'].include?(uri.path) && !uri.query && !uri.fragment
      "http://127.0.0.1:#{uri.port}"
    end
    def configure
      values = UI.inputbox(['Local web server'], [server], 'LuxKTC server')
      return unless values
      @server = checked_server(values.first)
      Sketchup.write_default('LuxKTC', 'server', @server)
    end
    def open_web; UI.openURL(server); end
    def show_studio
      raise 'The LuxKTC project studio is not loaded.' unless defined?(AJBoardKitchen::Studio)
      AJBoardKitchen::Studio.show
    end
    def active?
      @project && @root && @root.valid? && @root.model == Sketchup.active_model
    end
    def project; @project; end
    def status(message)
      AJBoardKitchen.update_status("LuxKTC: #{message}")
      begin
        AJBoardKitchen::Studio.sync_changed if defined?(AJBoardKitchen::Studio) && AJBoardKitchen::Studio.respond_to?(:sync_changed)
      rescue StandardError
        # A closed/reloading dialog must not interrupt a completed model save.
      end
    end
    def safe_id(value)
      raise ArgumentError, 'Invalid project or asset identifier' unless value.to_s.match?(/\A[A-Za-z0-9_-]{1,128}\z/)
      value.to_s
    end

    # SketchUp retains no request for the caller; keep each request until its
    # async completion. No Ruby network worker accesses the SketchUp model.
    def report_failure(handler, error, code = 0, data = {})
      if handler
        begin
          handler.call(error.message, code, data)
        rescue StandardError => callback_error
          AJBoardKitchen.guard { raise callback_error }
        end
      else
        AJBoardKitchen.guard { raise error }
      end
    end
    def request(method, path, payload = nil, on_error: nil, &callback)
      raise ArgumentError, 'Invalid API route' unless path.start_with?('/api/') && !path.include?('..')
      @requests ||= {}
      verb = case method
             when :get then Sketchup::Http::GET
             when :put then Sketchup::Http::PUT
             when :post then Sketchup::Http::POST
             when :delete then Sketchup::Http::DELETE
             else raise ArgumentError, 'Unsupported HTTP method'
             end
      req = Sketchup::Http::Request.new(server + path, verb)
      req.headers = {'Content-Type'=>'application/json', 'Accept'=>'application/json'}
      req.body = JSON.generate(payload) if payload
      request_model = Sketchup.active_model
      route_project_id = path[%r{\A/api/projects/([^/?]+)},1]
      request_project_id = active? && route_project_id == @project[:id] && @project[:id]
      @requests[req.object_id] = req
      started = req.start do |finished, response|
        @requests.delete(req.object_id)
        failure = nil; code = 0; data = {}
        begin
          raise 'The local web service did not respond. Start the LuxKTC server first.' unless response
          code = response.status_code.to_i
          body = response.body.to_s
          begin
            data = path.start_with?('/api/assets/') ? body : (body.empty? ? {} : JSON.parse(body, symbolize_names: true))
          rescue JSON::ParserError
            raise 'The local web service returned an invalid JSON response.'
          end
          if code == 409
            if active? && Sketchup.active_model == request_model && @project[:id] == request_project_id
              @dirty = true
              persist
            end
            message = "The web project has a newer revision (#{data[:current_revision]}). Your SketchUp edits are retained. Open the web project to compare, then choose which revision to keep before pulling."
            status(message)
            on_error ? failure = [RuntimeError.new(message),code,data] : UI.messagebox(message)
          elsif !code.between?(200,299)
            failure = [RuntimeError.new("Web request failed (HTTP #{code}): #{data.is_a?(Hash) ? data.fetch(:detail, 'Request failed') : 'Asset unavailable'}"),code,data]
          else
            callback.call(data, response) if callback
          end
        rescue StandardError => error
          failure = [error,code,data]
        end
        report_failure(on_error,*failure) if failure
      end
      if started == false
        @requests.delete(req.object_id)
        report_failure(on_error,RuntimeError.new('The local web request could not be started.'))
        return nil
      end
      req
    rescue StandardError => error
      @requests.delete(req.object_id) if req && @requests
      raise unless on_error
      report_failure(on_error,error)
      nil
    end

    def list_projects
      status('Reading shared projects...')
      request(:get, '/api/projects') do |data, _response|
        rows = data.is_a?(Array) ? data : data.fetch(:projects, [])
        raise 'Create a project in the web interface first.' if rows.empty?
        choices = rows.map { |row| "#{row[:name]} [#{row[:id]}]" }
        values = UI.inputbox(['Project'], [choices.first], [choices.join('|')], 'Pull LuxKTC project')
        next unless values
        at = choices.index(values.first)
        raise 'Select a listed project.' unless at
        pull(rows[at][:id])
      end
    end
    def pull(id = nil, on_success: nil, on_error: nil)
      @pull_serial = (@pull_serial || 0)+1
      pull_serial = @pull_serial
      id ||= active? && @project[:id]
      unless id
        return list_projects unless on_error
        return report_failure(on_error,RuntimeError.new('Select a shared project to pull.'))
      end
      unsupported = nil
      if active?
        begin
          candidate = capture_positions(ProjectBridge.copy(@project))
          if candidate != @project
            @project = candidate; @dirty = true
            @change_serial = (@change_serial || 0)+1
            persist
          end
        rescue UnsupportedEdit => error
          unsupported = error.message
          @dirty = true; persist
        end
      end
      if active? && @dirty
        text = unsupported ? "#{unsupported}\n\nPulling will discard these local model edits and restore the web project. Continue?" : 'Pulling replaces your unsaved local parametric edits, including cabinet moves. Continue?'
        answer = UI.messagebox(text, MB_YESNO)
        unless answer == IDYES
          report_failure(on_error,RuntimeError.new('Pull cancelled'),0,{cancelled:true}) if on_error
          return
        end
      end
      status('Downloading project and room textures...')
      serial = @change_serial
      pull_model = Sketchup.active_model
      native_checkpoint = active? && [@root.transformation.to_a,geometry_signature(@root)]
      request(:get, "/api/projects/#{safe_id(id)}", on_error: on_error) do |data, _response|
        download_textures(data, on_error: on_error) do
          raise 'A newer pull request replaced this download; the current model is retained.' unless pull_serial == @pull_serial
          raise 'The active model changed while the project was downloading; the model is retained.' unless pull_model == Sketchup.active_model
          raise 'Local edits changed while the project was downloading. They are retained; pull again when ready.' unless serial == @change_serial
          if native_checkpoint
            raise 'The model changed while the project was downloading. Your local edits are retained; pull again when ready.' unless active? && native_checkpoint == [@root.transformation.to_a,geometry_signature(@root)]
          end
          apply_project(data, dirty: false, preserve_camera:true)
          status("Project pulled at revision #{@project[:revision]}.")
          on_success.call(@project) if on_success
        end
      end
    rescue StandardError => error
      raise unless on_error
      report_failure(on_error,error)
    end
    def texture_cache
      path = File.join(Dir.tmpdir, 'LuxKTC', 'wall_textures')
      FileUtils.mkdir_p(path)
      path
    end
    def cached_texture(id)
      return nil if id.to_s.empty?
      prefix = File.join(texture_cache, safe_id(id))
      %w[.png .jpg].map { |ext| prefix+ext }.find { |path| File.file?(path) }
    end
    def download_textures(data, on_error: nil, &done)
      walls = data.fetch(:room, {}).fetch(:walls, [])
      # Only a perspective-corrected asset may texture a measured wall plane.
      ids = walls.map { |wall| wall[:rectified_asset_id] }.compact.uniq.reject { |id| cached_texture(id) }
      fetch_next = nil
      fetch_next = proc do
        if ids.empty?
          done.call
        else
          id = safe_id(ids.shift)
          request(:get, "/api/assets/#{id}", on_error: on_error) do |body, _response|
            bytes = body.dup.force_encoding(Encoding::BINARY)
            raise 'Wall texture exceeds the 12 MB limit.' if bytes.bytesize > 12*1024*1024
            ext = if bytes.start_with?("\x89PNG\r\n\x1a\n".b) then '.png'
                  elsif bytes.start_with?("\xff\xd8\xff".b) then '.jpg' end
            raise 'Wall texture must be a PNG or JPEG image.' unless ext
            File.binwrite(File.join(texture_cache, id+ext), bytes)
            fetch_next.call
          end
        end
      end
      fetch_next.call
    rescue StandardError => error
      raise unless on_error
      report_failure(on_error,error)
    end

    def persist
      return unless active?
      @root.set_attribute(DICT, 'project', JSON.generate(@project))
      @root.set_attribute(DICT, 'project_id', @project[:id])
      @root.set_attribute(DICT, 'revision', @project[:revision])
      @root.set_attribute(DICT, 'dirty', !!@dirty)
    end
    def apply_project(data, dirty: false, preserve_camera: false)
      raise 'Exit component editing before updating the shared project.' if Sketchup.active_model.active_path
      camera = Sketchup.active_model.active_view.camera if preserve_camera
      visibility = if preserve_camera
        AJBoardKitchen::CATEGORIES.filter_map do |category|
          layer = Sketchup.active_model.layers["AJ Board / #{category}"]
          [category,layer.visible?] if layer
        end.to_h
      else
        {}
      end
      candidate = ProjectBridge.copy(data)
      generated = ProjectBridge.generate(candidate)
      view = View.new(generated[:job])
      view.build_shared_project!(candidate)
      @project = candidate
      @root = view.root
      @dirty = dirty
      @change_serial = (@change_serial || 0)+1
      AJBoardKitchen.instance_variable_set(:@config, generated[:job][:settings])
      AJBoardKitchen.instance_variable_set(:@job, generated[:job])
      AJBoardKitchen.instance_variable_set(:@view, view)
      AJBoardKitchen.instance_variable_set(:@pending_edit, nil)
      persist
      Sketchup.active_model.active_view.camera = camera if camera
      visibility.each { |category,visible| view.tag(category).visible = visible }
      AJBoardKitchen.sync_dialog
      view
    end
    def rehydrate
      roots = Sketchup.active_model.entities.grep(Sketchup::Group).select { |group| group.get_attribute(DICT, 'project') }
      return false if roots.empty?
      found = roots.find { |group| Sketchup.active_model.selection.include?(group) } || roots.first
      data = JSON.parse(found.get_attribute(DICT, 'project'), symbolize_names: true)
      @root = found; @project = data; @dirty = found.get_attribute(DICT, 'dirty', false)
      # Attach to the existing model instead of rebuilding. Native moves,
      # visibility and the current camera survive extension reloads.
      raw = found.get_attribute(AJBoardKitchen::DICT,'job') || found.get_attribute(AJBoardScaffold::DICT,'job')
      job = raw ? JSON.parse(raw,symbolize_names:true) : ProjectBridge.generate(data)[:job]
      view = View.new(job)
      view.instance_variable_set(:@root,found)
      cabinets = []; motions = []; nest_root = nil
      view.walk(found) do |entity|
        next unless entity.respond_to?(:get_attribute)
        cabinets << entity if entity.get_attribute(AJBoardScaffold::DICT,'kind') == 'cabinet'
        motions << entity if entity.get_attribute(AJBoardScaffold::DICT,'motion')
        nest_root = entity if entity.respond_to?(:name) && entity.name == 'Nested sheets / no overlap'
      end
      view.instance_variable_set(:@cabinet_entities,cabinets)
      view.instance_variable_set(:@motions,motions)
      view.instance_variable_set(:@nest_root,nest_root)
      statistics = found.get_attribute(AJBoardScaffold::DICT,'statistics')
      view.instance_variable_set(:@statistics,JSON.parse(statistics,symbolize_names:true)) if statistics
      AJBoardKitchen.instance_variable_set(:@view,view)
      AJBoardKitchen.instance_variable_set(:@job,job)
      AJBoardKitchen.instance_variable_set(:@config,job[:settings])
      @change_serial = (@change_serial || 0)+1
      true
    end

    def capture_positions(candidate)
      view = AJBoardKitchen.instance_variable_get(:@view)
      identity = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
      transformed_parent = !@root.transformation.to_a.zip(identity).all? { |a,b| (a-b).abs < 0.000001 }
      live = []
      view.walk(@root) do |entity|
        next unless entity.respond_to?(:get_attribute)
        live << entity if entity.get_attribute(AJBoardScaffold::DICT,'kind') == 'cabinet'
        transformed_parent ||= entity.respond_to?(:transformation) && entity.get_attribute(AJBoardScaffold::DICT,'zone') && !entity.transformation.to_a.zip(identity).all? { |a,b| (a-b).abs < 0.000001 }
      end
      raise UnsupportedEdit, 'The project root or a cabinet zone was moved/scaled. Move individual cabinet roots or use the project cabinet editor.' if transformed_parent
      expected = view.cabinet_entities
      raise UnsupportedEdit, 'Cabinets were added or removed directly in the model. Use Add/Delete project cabinet so both clients retain the same intent.' unless live.length == expected.length && expected.all? { |entity| entity.valid? && live.include?(entity) }
      view.cabinet_entities.each do |entity|
        checkpoint = entity.get_attribute(DICT,'geometry_signature')
        raise UnsupportedEdit, 'Manufacturing geometry changed outside the cabinet editor. Your model is retained; use parametric edits or pull the saved project before pushing.' unless checkpoint && checkpoint == geometry_signature(entity)
        local_id = entity.get_attribute(AJBoardScaffold::DICT, 'id')
        spec = candidate[:design][:cabinets].find { |cab| cab[:local_id] == local_id }
        unless spec
          accessory = AJBoardKitchen.instance_variable_get(:@job)[:cabinets].find { |cab| cab[:id] == local_id }
          expected_pose = accessory && view.pose(accessory[:pose]).to_a
          raise UnsupportedEdit, 'Generated worktops and scribes were moved directly. Move their base cabinets, then Push to regenerate matching accessories.' unless expected_pose && entity.transformation.to_a.zip(expected_pose).all? { |a,b| (a-b).abs < 0.000001 }
          next
        end
        transform = entity.transformation
        x_axis = transform.xaxis; y_axis = transform.yaxis; z_axis = transform.zaxis
        valid_frame = transform.to_a.all?(&:finite?) && [x_axis.length,y_axis.length,z_axis.length].all? { |n| (n-1).abs < 0.00001 } &&
          x_axis.dot(y_axis).abs < 0.00001 && x_axis.dot(z_axis).abs < 0.00001 && y_axis.dot(z_axis).abs < 0.00001 &&
          x_axis.cross(y_axis).dot(z_axis) > 0.99999 && z_axis.dot(Z_AXIS) > 0.99999
        raise UnsupportedEdit, 'Scaled, mirrored or tilted cabinets cannot be pushed. Use Edit selected project cabinet for dimensions.' unless valid_frame
        wall = candidate[:room][:walls].find { |row| row[:id] == spec[:wall_id] }
        angle = wall.fetch(:rotation_deg, 0).to_f*Math::PI/180
        origin = wall.fetch(:origin_mm, [0,0,0])
        point = transform.origin.to_a.map { |n| n*25.4 }
        dx = point[0]-origin[0]; dy = point[1]-origin[1]
        spec[:x_mm] = (dx*Math.cos(angle)+dy*Math.sin(angle)).round(6)
        spec[:y_mm] = (-dx*Math.sin(angle)+dy*Math.cos(angle)).round(6)
        spec[:z_mm] = (point[2]-origin[2]).round(6)
        rotation = Math.atan2(transform.xaxis.y,transform.xaxis.x)*180/Math::PI-wall.fetch(:rotation_deg,0)
        spec[:rotation_deg] = rotation.round(6) unless ((rotation-spec.fetch(:rotation_deg,0)+180)%360-180).abs < 0.000001
      end
      candidate
    end
    def geometry_signature(entity, root: true)
      values = [entity.class.name]
      if entity.respond_to?(:definition)
        name = entity.respond_to?(:name) ? entity.name : ''
        # Preview annotations never change the underlying manufacturing parts.
        return 'overlay' if !root && name.match?(/\A(?:Labels \/|Grooves \/|Drilling \/|Band \/|Edge machining \/|[BWR]\d+ dimensions\z)/)
        motion = entity.get_attribute(AJBoardScaffold::DICT,'motion')
        values << entity.transformation.to_a.map { |number| number.round(8) } unless root || motion
        values << entity.material&.name
        values << entity.definition.entities.map { |child| geometry_signature(child,root:false) }.sort_by(&:to_s)
      elsif defined?(Sketchup::Edge) && entity.is_a?(Sketchup::Edge)
        values << [entity.start.position.to_a,entity.end.position.to_a].map { |point| point.map { |number| number.round(8) } }.sort
      elsif defined?(Sketchup::Face) && entity.is_a?(Sketchup::Face)
        values << entity.loops.map { |loop| loop.vertices.map { |vertex| vertex.position.to_a.map { |number| number.round(8) } } }.sort_by(&:to_s)
        values << entity.material&.name << entity.back_material&.name
      end
      Digest::SHA256.hexdigest(JSON.generate(values))
    end
    def push(on_success: nil, on_error: nil)
      raise 'Pull a shared project first.' unless active?
      raise 'Exit component editing before pushing the project.' if Sketchup.active_model.active_path
      push_model = Sketchup.active_model
      candidate = capture_positions(ProjectBridge.copy(@project))
      built_design = AJBoardKitchen.instance_variable_get(:@job)&.dig(:input_manifest,:design)
      if candidate[:design] != built_design
        # Native root moves change worktop runs/cutouts and room placement.
        # Materialize the same design locally before sending its generated
        # job, so export, saved attributes and nesting describe one revision.
        apply_project(candidate,dirty:true,preserve_camera:true)
        candidate = ProjectBridge.copy(@project)
      end
      generated = ProjectBridge.generate(candidate)
      # Persist captured local moves before the asynchronous request, including
      # a conflict or an interrupted network connection.
      @project = candidate; @dirty = true; persist
      @change_serial = (@change_serial || 0)+1
      sent = JSON.generate(candidate)
      status('Saving parametric edits to the common database...')
      request(:put, "/api/projects/#{safe_id(candidate[:id])}", {base_revision: candidate[:revision], project: candidate, generated: generated}, on_error: on_error) do |saved, _response|
        if !active? || @project[:id] != candidate[:id] || push_model != Sketchup.active_model
          status("Saved #{candidate[:name]} at revision #{saved[:revision]}.")
          on_success.call(saved) if on_success
          next
        end
        native_changed = false
        begin
          observed = capture_positions(ProjectBridge.copy(@project))
          if observed != @project
            @project = observed
            native_changed = true
          end
        rescue UnsupportedEdit
          # Keep the untouched local model and mark it unsent. Completion of
          # an older request must never approve unsupported newer edits.
          native_changed = true
        end
        if !native_changed && JSON.generate(@project) == sent
          @project = saved; @dirty = false
          generated[:job][:project_revision] = saved[:revision]
          AJBoardKitchen.instance_variable_set(:@job,generated[:job])
          AJBoardKitchen.instance_variable_get(:@view).instance_variable_set(:@job,generated[:job])
          @root.set_attribute(AJBoardKitchen::DICT,'job',JSON.generate(generated[:job]))
          @root.set_attribute(AJBoardScaffold::DICT,'job',JSON.generate(generated[:job]))
        else
          # Local edits made while the request was in flight survive. Their
          # next save uses the revision just accepted by the server.
          @project[:revision] = saved[:revision]
          @project[:manufacturing] = saved[:manufacturing]
          @dirty = true
        end
        @change_serial = (@change_serial || 0)+1
        persist
        status("Saved revision #{saved[:revision]}#{@dirty ? '; newer local edits are still unsent' : ''}.")
        on_success.call(saved) if on_success
      end
    rescue StandardError => error
      raise unless on_error
      report_failure(on_error,error)
    end

    def edit(local_id = nil)
      raise 'Pull a shared project first.' unless active?
      local_id ||= AJBoardKitchen.cabinet_id_from((Sketchup.active_model.active_path || []) + Sketchup.active_model.selection.to_a)
      candidate = capture_positions(ProjectBridge.copy(@project))
      row = candidate[:design][:cabinets].find { |cab| cab[:local_id] == local_id }
      raise 'Select a cabinet in the shared project first.' unless row
      options = row.fetch(:options, {})
      defaults = @project[:design].fetch(:settings, {})
      labels = ['Width (mm)', 'Height (mm)', 'Depth (mm)', 'Wall X (mm)', 'Wall Y (mm)', 'Wall Z (mm)', 'Rotation (degrees)', 'Connector', 'Hinges', 'Carcass band (mm)', 'Front band (mm)']
      values = %i[width_mm height_mm depth_mm x_mm y_mm z_mm rotation_deg].map { |key| row.fetch(key,0) }
      values += [options.fetch(:joinery, defaults.fetch(:joinery,'minifix')), options.fetch(:hinge,defaults.fetch(:hinge,'cup35_screw')), options.fetch(:edge,defaults.fetch(:edge,1)), options.fetch(:front_edge,defaults.fetch(:front_edge,1))]
      lists = Array.new(7,'') + ['minifix|screw|minifix_dowel|rafix|ovvo_od830|dowel', 'cup35_screw|cup35_dowel|none', '0|0.5|1|2', '0|0.5|1|2']
      changed = UI.inputbox(labels, values, lists, "LuxKTC #{local_id} / parametric cabinet")
      return unless changed
      target = candidate[:design][:cabinets].find { |cab| cab[:id] == row[:id] }
      %i[width_mm height_mm depth_mm x_mm y_mm z_mm rotation_deg].each_with_index { |key,index| target[key] = Float(changed[index]) }
      target[:options] ||= {}
      target[:options].merge!(joinery: changed[7], hinge: changed[8], edge: Float(changed[9]), front_edge: Float(changed[10]))
      apply_project(candidate, dirty: true, preserve_camera:true)
      status('Cabinet changed locally. Push edits to update the web project, BOM and quote.')
    end
    def add
      raise 'Pull a shared project first.' unless active?
      candidate = capture_positions(ProjectBridge.copy(@project))
      walls = candidate[:room][:walls]
      raise 'Create a measured wall in the web interface first.' if walls.empty?
      wall_choices = walls.map { |wall| "#{wall.fetch(:name,'Wall')} [#{wall[:id]}]" }
      selected = UI.inputbox(['Cabinet family','Wall'],[ProjectBridge::TYPES.first,wall_choices.first],[ProjectBridge::TYPES.join('|'),wall_choices.join('|')],'Add LuxKTC cabinet')
      return unless selected
      type = selected[0]
      raise 'Select a supported cabinet family.' unless ProjectBridge::TYPES.include?(type)
      wall = walls[wall_choices.index(selected[1]) || -1]
      wall_unit = type.start_with?('wall_'); tall = type.start_with?('tall_')
      values = UI.inputbox(['Name','Width (mm)','Height (mm)','Depth (mm)','Wall X (mm)','Wall Y (mm)','Wall Z (mm)','Rotation (degrees)'],[type.tr('_',' '),600,tall ? 2100 : wall_unit ? 600 : 720,wall_unit ? 330 : 560,0,0,wall_unit ? 1600 : 0,0], 'Cabinet measurements')
      return unless values
      prefix = wall_unit ? 'W' : 'B'
      count = candidate[:design][:cabinets].select { |cab| cab[:local_id].start_with?(prefix) }.map { |cab| cab[:local_id][1..].to_i }.max.to_i+1
      row = {id:SecureRandom.uuid,local_id:format('%s%02d',prefix,count),type:type,wall_id:wall[:id],name:values[0],options:{}}
      %i[width_mm height_mm depth_mm x_mm y_mm z_mm rotation_deg].each_with_index { |key,index| row[key] = Float(values[index+1]) }
      candidate[:design][:cabinets] << row
      apply_project(candidate,dirty:true,preserve_camera:true)
      status('Cabinet added locally. Push edits to save it in the web project.')
    end
    def delete
      raise 'Pull a shared project first.' unless active?
      id = AJBoardKitchen.cabinet_id_from((Sketchup.active_model.active_path || [])+Sketchup.active_model.selection.to_a)
      candidate = capture_positions(ProjectBridge.copy(@project))
      row = candidate[:design][:cabinets].find { |cab| cab[:local_id] == id }
      raise 'Select a cabinet in the active shared project first.' unless row
      return unless UI.messagebox("Delete #{id} / #{row[:name]} from this project? The change remains local until you push.",MB_YESNO) == IDYES
      candidate[:design][:cabinets].delete(row)
      apply_project(candidate,dirty:true,preserve_camera:true)
      status('Cabinet deleted locally. Push edits to update the web project.')
    end
    def renest(input = {})
      raise 'Pull a shared project first.' unless active?
      candidate = capture_positions(ProjectBridge.copy(@project))
      candidate[:design][:settings] ||= {}
      candidate[:design][:settings].merge!(input.transform_keys(&:to_sym).slice(:sheet_w,:sheet_h,:kerf,:margin))
      apply_project(candidate, dirty: true, preserve_camera:true)
      AJBoardKitchen.instance_variable_get(:@view).focus_nesting
    end

    def install
      return if @toolbar && @toolbar_version == 2
      @toolbar.hide if @toolbar
      @toolbar_version = 2
      @toolbar = UI::Toolbar.new('LuxKTC shared project')
      menu = UI.menu('Extensions').add_submenu('LuxKTC shared project')
      actions = [['Project studio', :show_studio], ['Open web project', :open_web], ['Pull shared project', :list_projects], ['Push SketchUp edits', :push], ['Add project cabinet', :add], ['Edit selected project cabinet', :edit], ['Delete selected project cabinet', :delete], ['Configure local server', :configure]]
      actions.each do |label,method|
        command = UI::Command.new(label) { AJBoardKitchen.guard { public_send(method) } }
        command.tooltip = label
        command.small_icon = File.join(AJBoardKitchen::ROOT, 'assets', method == :edit ? 'edit.png' : 'settings.png')
        command.large_icon = command.small_icon
        @toolbar.add_item(command)
        menu.add_item(command)
      end
      [['Room walls','Room walls'],['Room measurements','Room measurements'],['Cabinet measurements','Cabinet measurements']].each do |label,category|
        command = UI::Command.new("Toggle #{label.downcase}") { AJBoardKitchen.guard { AJBoardKitchen.toggle(category) } }
        command.tooltip = "Toggle #{label.downcase}"
        command.small_icon = File.join(AJBoardKitchen::ROOT, 'assets', 'labels.png')
        command.large_icon = command.small_icon
        @toolbar.add_item(command); menu.add_item(command)
      end
      @toolbar.show
    end
  end

  class View
    def build_shared_project!(project)
      started = false
      raise 'Exit component editing before building a shared project.' if @model.active_path
      old = @model.entities.grep(Sketchup::Group).select { |group| group.get_attribute(Sync::DICT, 'project_id') == project[:id] }
      begin_build; started = true
      @root.name = "LuxKTC / #{project[:name]} / revision #{project[:revision]}"
      @root.set_attribute(AJBoardKitchen::DICT, 'owned', true)
      @root.set_attribute(AJBoardKitchen::DICT, 'job', JSON.generate(@job))
      @root.set_attribute(Sync::DICT, 'project_id', project[:id])
      @root.set_attribute(Sync::DICT, 'project', JSON.generate(project))
      @root.set_attribute(Sync::DICT, 'revision', project[:revision])
      @job[:cabinets].each { |cab| add_cabinet(cab) }
      add_room_reference(project)
      add_cabinet_measurements
      @cabinet_entities.each { |entity| entity.set_attribute(Sync::DICT,'geometry_signature',Sync.geometry_signature(entity)) }
      others = @model.entities.to_a.reject { |entity| entity == @root || old.include?(entity) }
      max_x = (others + [@root]).filter_map { |entity| entity.bounds.max.x.to_f*25.4 if entity.respond_to?(:bounds) && !entity.bounds.empty? }.max || 0
      draw_nesting(max_x+1000)
      old.each(&:erase!)
      finish_build
      tag('Room walls').visible = true
      tag('Room measurements').visible = true
      tag('Cabinet measurements').visible = true
      focus_kitchen unless @cabinet_entities.empty?
      @root
    rescue StandardError => error
      abort_build(error) if started
      raise
    end
    def dimension(entities, a, b, offset, category)
      return if a == b
      entity = entities.add_dimension_linear(pt(a), pt(b), vec(offset).normalize*mm(100))
      entity.layer = tag(category)
      entity
    end
    def add_room_reference(project)
      project.fetch(:room, {}).fetch(:walls, []).each do |wall|
        w = wall.fetch(:width_mm).to_f; h = wall.fetch(:height_mm).to_f
        raise 'Wall width and height must be positive.' unless w.positive? && h.positive?
        group = @root.entities.add_group
        group.name = wall.fetch(:name, 'Measured wall')
        group.layer = tag('Room walls')
        group.transformation = pose([*wall.fetch(:origin_mm,[0,0,0]),wall.fetch(:rotation_deg,0)])
        group.set_attribute(Sync::DICT, 'wall', JSON.generate(wall))
        surface = face(group.entities, [[0,0,0],[w,0,0],[w,0,h],[0,0,h]])
        texture = Sync.cached_texture(wall[:rectified_asset_id])
        if texture
          material = @model.materials["LuxKTC wall #{wall[:id]}"] || @model.materials.add("LuxKTC wall #{wall[:id]}")
          material.texture = texture
          material.texture.size = [mm(w),mm(h)]
          surface.material = material; surface.back_material = material
          mapping = [[0,0,0],[w,0,0],[w,0,h],[0,0,h]].zip([[0,0,0],[1,0,0],[1,1,0],[0,1,0]]).flat_map { |point,uv| [pt(point),Geom::Point3d.new(uv)] }
          surface.position_material(material,mapping,true)
          surface.position_material(material,mapping,false)
        else
          surface.material = material('Back')
        end
        # Door/window openings become real apertures; service points remain
        # visible outlines rather than punched wall holes.
        wall.fetch(:openings,[]).each do |opening|
          x = opening[:x_mm].to_f; z = opening[:z_mm].to_f; ow = opening[:width_mm].to_f; oh = opening[:height_mm].to_f
          next unless ow.positive? && oh.positive? && x >= 0 && z >= 0 && x+ow <= w+0.001 && z+oh <= h+0.001
          points = [[x,0,z],[x+ow,0,z],[x+ow,0,z+oh],[x,0,z+oh]]
          if %w[door window].include?(opening[:type])
            face(group.entities,points).erase!
          else
            points.each_with_index do |a,index|
              b = points[(index+1)%4]
              group.entities.add_line(pt([a[0],-0.5,a[2]]),pt([b[0],-0.5,b[2]]))
            end
          end
        end
        thickness = wall.fetch(:thickness_mm,150).to_f
        # Room material goes behind the wall datum (+Y); cabinets occupy -Y.
        surface.pushpull(mm(thickness)*(surface.normal.y > 0 ? 1 : -1)) if surface.valid? && thickness.positive?
        measurements = @root.entities.add_group
        measurements.name = "#{group.name} measurements#{wall[:measurements_confirmed] ? '' : ' / estimated'}"
        measurements.layer = tag('Room measurements')
        measurements.transformation = group.transformation
        dimension(measurements.entities,[0,-2,0],[w,-2,0],[0,0,-1],'Room measurements')
        dimension(measurements.entities,[0,-2,0],[0,-2,h],[-1,0,0],'Room measurements')
        wall.fetch(:openings,[]).each do |opening|
          x = opening[:x_mm].to_f; z = opening[:z_mm].to_f
          ow = opening[:width_mm].to_f; oh = opening[:height_mm].to_f
          next unless ow.positive? && oh.positive?
          dimension(measurements.entities,[x,-3,z],[x+ow,-3,z],[0,0,-1],'Room measurements')
          dimension(measurements.entities,[x,-3,z],[x,-3,z+oh],[-1,0,0],'Room measurements')
        end
      end
    end
    def add_cabinet_measurements
      @job[:cabinets].each do |cab|
        next if cab[:accessory]
        owner = @cabinet_entities.find { |entity| entity.get_attribute(AJBoardScaffold::DICT,'id') == cab[:id] }
        group = owner.entities.add_group; group.name = "#{cab[:id]} dimensions"; group.layer = tag('Cabinet measurements')
        base = cab[:type].start_with?('wall_') ? 0 : 100
        dimension(group.entities,[0,-cab[:d]-22,base],[cab[:w],-cab[:d]-22,base],[0,0,-1],'Cabinet measurements')
        dimension(group.entities,[0,-cab[:d]-22,base],[0,-cab[:d]-22,base+cab[:h]],[-1,0,0],'Cabinet measurements')
        dimension(group.entities,[cab[:w]+22,0,base],[cab[:w]+22,-cab[:d],base],[1,0,0],'Cabinet measurements')
      end
    end
  end
end
