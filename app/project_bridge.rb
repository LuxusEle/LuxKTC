# frozen_string_literal: true
# Headless manufacturing bridge. Never load aj_board_kitchen.rb in the web worker.
require_relative 'engineering'
require 'json'
require 'digest'

module AJBoardKitchen
  module ProjectBridge
    extend self
    TYPES = %w[base_single base_double base_gola base_hob base_drawers_2 base_drawers_3 base_drawers_4 base_sink base_pullout tall_pantry tall_oven_micro wall_single wall_double wall_open wall_hood].freeze unless const_defined?(:TYPES)

    def copy(value); JSON.parse(JSON.generate(value), symbolize_names: true); end
    def number(value, name)
      result = Float(value)
      raise ArgumentError, "#{name} must be finite" unless result.finite?
      result
    end
    def uuid(*values)
      hex = Digest::SHA256.hexdigest(values.join('/'))[0, 32]
      "#{hex[0,8]}-#{hex[8,4]}-5#{hex[13,3]}-a#{hex[17,3]}-#{hex[20,12]}"
    end
    def remap(value, from, to)
      case value
      when Hash then value.to_h { |key, child| [key, remap(child, from, to)] }
      when Array then value.map { |child| remap(child, from, to) }
      when String then value == from || value.start_with?(from + '-') ? to + value[from.length..] : value
      else value
      end
    end

    def accessories(project, specs, walls, conf)
      choices = project.fetch(:design).fetch(:accessories, {})
      band = number(choices.fetch(:end_scribe_mm,0), 'End scribe')
      raise ArgumentError, 'End scribe must be 0 to 100 mm' unless band.between?(0,100)
      return [] unless choices[:worktops] || band.positive?
      walls.each_with_index.filter_map do |wall,index|
        rows = specs.select { |spec| spec[:wall_id] == wall[:id] && !spec[:type].start_with?('wall_') }.sort_by { |spec| spec.fetch(:x_mm,0) }
        next if rows.empty?
        raise ArgumentError, 'Automatic accessories currently require straight cabinets aligned with their wall.' unless rows.all? { |spec| number(spec.fetch(:rotation_deg,0),'Cabinet rotation').abs < 0.001 }
        local_id = format('R%02d',index+1)
        parts = []
        add = proc do |role,name,w,h,t,origin,u,v,n,material,holes=[]|
          parts << {id:"#{local_id}-#{role}",name:name,kind:'panel',w:w.to_f,h:h.to_f,t:t.to_f,o:origin,u:u,v:v,n:n,outline:S.rectangle(w,h),holes:holes,
            material:material,category:material == 'Worktop' ? 'Worktop' : 'Carcass',operations:[],edges:{},grain:'none'}
        end
        if band.positive?
          first = rows.first; last = rows.max_by { |spec| spec.fetch(:x_mm,0)+spec[:width_mm] }
          first_x = number(first.fetch(:x_mm,0),'Cabinet X'); end_x = number(last.fetch(:x_mm,0),'Cabinet X')+last[:width_mm]
          wall_width = number(wall.fetch(:width_mm),'Wall width')
          raise ArgumentError, 'Selected end scribes do not fit inside the measured wall.' if first_x-band < -0.001 || end_x+band > wall_width+0.001
          [[first,'left',first_x-band],[last,'right',end_x]].each do |spec,side,x|
            add.call("scribe-#{side}","#{side.capitalize} scribe",band,spec[:height_mm],18,[x,spec.fetch(:y_mm,0)-spec[:depth_mm],spec.fetch(:z_mm,0)+100],X,Z,NY,'Front')
          end
        end
        if choices[:worktops]
          lower = rows.reject { |spec| spec[:type].start_with?('tall_') }
          runs = []
          lower.each do |spec|
            previous = runs.last&.last
            connected = previous && (spec.fetch(:x_mm,0)-previous.fetch(:x_mm,0)-previous[:width_mm]).abs < 0.001 &&
              (spec.fetch(:y_mm,0)-previous.fetch(:y_mm,0)).abs < 0.001 && (spec.fetch(:z_mm,0)+spec[:height_mm]-previous.fetch(:z_mm,0)-previous[:height_mm]).abs < 0.001
            connected ? runs.last << spec : runs << [spec]
          end
          runs.each do |run|
            left = run.first.fetch(:x_mm,0).to_f
            right = run.last.fetch(:x_mm,0).to_f+run.last[:width_mm]
            right += band if band.positive? && run.last.equal?(rows.last)
            depth = run.map { |spec| spec[:depth_mm] }.max.to_f
            front = run.first.fetch(:y_mm,0)-depth-40
            holes = run.filter_map do |spec|
              sink = spec[:type] == 'base_sink'
              hob = spec[:type] == 'base_hob' || spec.fetch(:options, {})[:role] == 'hob'
              next unless sink || hob
              cw,ch,inset = sink ? [440.0,370.0,65.0] : [560.0,490.0,35.0]
              raise ArgumentError, 'Provisional appliance cutout does not fit this worktop; confirm the selected appliance.' unless cw+20 <= spec[:width_mm] && ch+20 <= depth+60
              x = spec.fetch(:x_mm,0)-left+(spec[:width_mm]-cw)/2
              y = spec.fetch(:y_mm,0)-spec[:depth_mm]+inset-front
              S.rectangle(cw,ch).map { |xx,yy| [x+xx,y+yy] }
            end
            role = "worktop-#{run.first[:id]}"
            add.call(role,'Worktop - TEST appliance cutouts',right-left,depth+60,30,[left,front,run.first.fetch(:z_mm,0)+100+run.first[:height_mm]],X,Y,Z,'Worktop',holes)
          end
        end
        next if parts.empty?
        {id:local_id,uuid:uuid(project[:id],wall[:id],'accessories'),type:'room',accessory:true,name:'Room accessories',mode:'board',
          w:wall[:width_mm],h:wall[:height_mm],d:0,pose:[*wall.fetch(:origin_mm,[0,0,0]),wall.fetch(:rotation_deg,0)],options:{config:conf},parts:parts,motions:[],hardware:[],warnings:['Worktop cutouts are provisional; confirm selected appliance templates.']}
      end
    end

    def generate(input)
      project = copy(input)
      raise ArgumentError, 'Project schema_version must be 1' unless project[:schema_version] == 1
      raise ArgumentError, 'Project identity is required' if project[:id].to_s.empty?
      design = project.fetch(:design)
      raise ArgumentError, 'The shared board engine currently supports modern_gola only' unless design.fetch(:style, 'modern_gola') == 'modern_gola'
      conf = AJBoardKitchen.settings(design.fetch(:settings, {}))
      specs = design.fetch(:cabinets, [])
      raise ArgumentError, 'Cabinets must be an array' unless specs.is_a?(Array)
      walls = project.fetch(:room, {}).fetch(:walls, [])
      raise ArgumentError, 'Wall IDs must be unique' unless walls.map { |wall| wall[:id] }.uniq.length == walls.length
      raise ArgumentError, 'Cabinet identities must be unique' unless specs.map { |cab| cab[:id] }.uniq.length == specs.length
      raise ArgumentError, 'Cabinet local IDs must be unique' unless specs.map { |cab| cab[:local_id] }.uniq.length == specs.length
      cabinets = specs.map do |spec|
        local_id = spec.fetch(:local_id).to_s
        raise ArgumentError, 'Cabinet local IDs must look like B01 or W01' unless local_id.match?(/\A[BW]\d{2,4}\z/)
        raise ArgumentError, 'Cabinet UUID is required' if spec[:id].to_s.empty?
        type = spec.fetch(:type).to_s
        raise ArgumentError, "Cabinet family #{type} is not qualified for the shared board engine" unless TYPES.include?(type)
        wall = walls.find { |candidate| candidate[:id] == spec[:wall_id] }
        raise ArgumentError, "Unknown wall for #{local_id}" unless wall
        opts = (spec[:options] || {}).transform_keys(&:to_sym)
        local = AJBoardKitchen.settings(conf.merge(opts.slice(:joinery, :hinge, :edge, :front_edge)))
        w, h, d = %i[width_mm height_mm depth_mm].map { |key| number(spec.fetch(key), key) }
        raise ArgumentError, "#{local_id}: dimensions must be positive" unless [w,h,d].all?(&:positive?)
        if type == 'tall_oven_micro'
          raise ArgumentError, 'Two-oven towers require 600 mm width, 1900 to 2300 mm height and 560 to 650 mm depth.' unless (w-600).abs < 0.001 && h.between?(1900,2300) && d.between?(560,650)
        end
        if type == 'base_hob' || opts[:role] == 'hob'
          raise ArgumentError, 'Hob role requires a 600 mm base_gola cabinet at least 560 mm deep.' unless %w[base_gola base_hob].include?(type) && (w-600).abs < 0.001 && d >= 560
        end
        raise ArgumentError, 'Sink cabinets require at least 550 mm width.' if type == 'base_sink' && w < 550
        wall_unit = type.start_with?('wall_')
        raise ArgumentError, 'Use W IDs for wall units and B IDs for base/tall units' unless local_id.start_with?(wall_unit ? 'W' : 'B')
        # Board currently recognizes a legacy B05 hob. Isolate that local-ID
        # convention here; all public identity comes from the project UUIDs.
        internal = type == 'base_hob' || opts[:role] == 'hob' ? 'B05' : "KTC_#{local_id}"
        actual_type = type == 'base_hob' ? 'base_gola' : type
        angle = number(wall.fetch(:rotation_deg, 0), 'wall rotation')
        origin = wall.fetch(:origin_mm, [0,0,0]).map { |n| number(n, 'wall origin') }
        raise ArgumentError, 'Wall origin must contain XYZ' unless origin.length == 3
        x, y, z = %i[x_mm y_mm z_mm].map { |key| number(spec.fetch(key, 0), key) }
        radians = angle * Math::PI / 180.0
        pose = [origin[0]+x*Math.cos(radians)-y*Math.sin(radians), origin[1]+x*Math.sin(radians)+y*Math.cos(radians), origin[2]+z, angle+number(spec.fetch(:rotation_deg, 0), 'cabinet rotation')]
        options = {config: local, joinery: local[:joinery]}
        options[:front_system] = 'gola' if design.fetch(:style, 'modern_gola') == 'modern_gola' && !wall_unit
        cabinet = Board.new(actual_type, id: internal, w: w, h: h, d: d, pose: pose, options: options).data
        cabinet = remap(cabinet, internal, local_id)
        cabinet.merge!(id: local_id, uuid: spec[:id], type: type, wall_id: wall[:id], name: spec.fetch(:name, cabinet[:name]))
        cabinet
      end
      cabinets.concat(accessories(project,specs,walls,conf))
      # Reuse existing part numbers after a reorder; new physical part roles get
      # new numbers. A display number is never a cross-client identity.
      previous = project.dig(:manufacturing, :job, :cabinets).to_a.flat_map { |cab| cab[:parts] || [] }
      known = previous.select { |part| part[:uuid] && part[:number] }.to_h { |part| [part[:uuid], part[:number]] }
      counter = previous.map { |part| part[:number].to_s.delete_prefix('P').to_i }.max || 0
      used = {}
      cabinets.each do |cab|
        cab[:parts] = cab[:parts].filter_map do |part|
          next if part[:kind] == 'profile' && part[:section] == 'handle'
          part.delete(:number_after_legacy)
          part[:edges] = conf[:edge_overrides][part[:id]] if part[:kind] == 'panel' && conf[:edge_overrides].key?(part[:id])
          part = AJBoardKitchen.core_part(part)
          part[:uuid] = uuid(project[:id], cab[:uuid], part[:id].sub(/\A#{Regexp.escape(cab[:id])}-/, ''))
          saved = known[part[:uuid]]
          if saved && !used[saved]
            part[:number] = saved
          else
            begin
              counter += 1
              part[:number] = format('P%03d', counter)
            end while used[part[:number]]
          end
          used[part[:number]] = true
          part.merge(cabinet_id: cab[:id], cabinet_uuid: cab[:uuid], cabinet_name: cab[:name])
        end
        cab[:front_system] = 'handleless' if cab[:front_system] == 'handled'
      end
      width = cabinets.map { |cab| cab[:pose][0] + cab[:w] + cab[:d] }.max || 0.0
      job = {id: project[:id], name: project.fetch(:name, 'LuxKTC project'), version: AJBoardKitchen::VERSION, schema_version: 1,
        settings: conf, width: width, cabinets: cabinets, fixtures: [], room: project[:room], project_revision: project[:revision],
        input_manifest: {design:copy(design), walls:walls.map { |wall| %i[id width_mm height_mm thickness_mm origin_mm rotation_deg openings].to_h { |key| [key,wall[key]] } }},
        status: 'WORKSHOP TEST - measured layout; hardware recipes require workshop approval',
        notes: ['Ruby board engine is the manufacturing authority.', 'Finished sizes and core sizes retain side-specific edgeband allowances.', 'Grooved backs and rear stretchers use the existing board rules.', 'Wall photographs and measurements are room references, not manufacturing parts.']}
      AJBoardKitchen.validate_job(job)
      {job: job, nesting: AJBoardKitchen.nest(job)}
    end
  end

  def project_job(project); ProjectBridge.generate(project)[:job]; end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise ArgumentError, 'Usage: project_bridge.rb input.json output.json' unless ARGV.length == 2
    result = AJBoardKitchen::ProjectBridge.generate(JSON.parse(File.read(ARGV[0]), symbolize_names: true))
    File.write(ARGV[1], JSON.generate(result))
  rescue StandardError => error
    warn "LuxKTC manufacturing bridge: #{error.class}: #{error.message}"
    exit 1
  end
end
