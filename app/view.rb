# frozen_string_literal: true
require_relative 'export' unless defined?(AJBoardKitchen::Export)

module AJBoardKitchen
  remove_const(:CATEGORIES) if const_defined?(:CATEGORIES, false)
  CATEGORIES=%w[Carcass Backs Stretchers Doors].concat(['Drawer faces','Drawer boxes','Connectors','Hinges','Runners','Gola','Finger pulls','Upper covers','Edgebands','Machining','Part numbers','Nesting','Appliances','Plinth','Worktop','Room walls','Room measurements','Cabinet measurements']).freeze
  class View < S::Adapter
    attr_reader :root,:job,:statistics,:nest_root
    def geometry_key(p)
      grooves=p[:operations].select { |o| o[:kind]=='groove' }.map { |o| o.slice(:face,:x,:y,:w,:h,:depth) }
      Digest::SHA256.hexdigest(super+JSON.generate(grooves))
    end
    def cut_grooves(entities,p,xy=proc { |x,y| [x,y] })
      p[:operations].select { |o| o[:kind]=='groove' }.each do |o|
        z=o[:face]=='A' ? 0 : p[:t]
        f=face(entities,AJBoardKitchen.groove_outline(o).map { |x,y| [*xy.call(x,y),z] })
        f.reverse! if (o[:face]=='A' && f.normal.z>0) || (o[:face]=='B' && f.normal.z<0)
        f.pushpull(-mm(o[:depth]))
      end
    end
    def part_definition(p)
      key=geometry_key(p)
      @cache[key] ||= begin
        d=@model.definitions.add("AJ Board Solid #{key[0,12]}")
        prism(d.entities,p[:outline],p[:holes],p[:t],p.fetch(:miter_start,0),p.fetch(:miter_end,0))
        cut_grooves(d.entities,p)
        @statistics[:unique_solids]+=1
        d
      end
    end
    def material(name)
      @materials[name] ||= begin
        colors={'Carcass'=>[223,221,211],'Front'=>[72,99,93],'Drawer'=>[185,144,97],'Back'=>[210,207,195],'Graphite'=>[35,39,40],'Hardware'=>[155,163,166],'Aluminum'=>[157,167,171],'Worktop'=>[219,216,202],'Appliance'=>[28,32,34],'Glass'=>[45,55,57],'Drilling'=>[211,77,38],'Edgeband'=>[172,140,75]}
        m=@model.materials["AJ Board / #{name}"]||@model.materials.add("AJ Board / #{name}")
        m.color=Sketchup::Color.new(*(colors[name]||[160,170,166]));m
      end
    end
    def tag(name); @model.layers["AJ Board / #{name}"]||@model.layers.add("AJ Board / #{name}"); end
    def text_on_plane(entities,text,x,y,z,size,tag_name='Part numbers',color:'Graphite',width:nil)
      g=entities.add_group;g.name=text;g.layer=tag(tag_name)
      made=g.entities.add_3d_text(text,TextAlignLeft,'Arial',false,false,mm(size),0,0,true,0)
      unless made && g.entities.length>0
        Annotations.stroke_lines(text,0,0,size).each { |a,b| g.entities.add_line(pt([*a,0]),pt([*b,0])) }
      end
      if width && g.bounds.width>mm(width)
        factor=mm(width)/g.bounds.width
        g.entities.transform_entities(Geom::Transformation.scaling(factor),g.entities.to_a)
      end
      # Explicit front/back colors keep flat lettering legible from either side.
      ink=color=='Light' ? Sketchup::Color.new(250,247,231) : material(color)
      g.entities.each do |e|
        e.material=ink if e.respond_to?(:material=)
        e.back_material=ink if e.respond_to?(:back_material=)
      end
      g.transformation=Geom::Transformation.translation(pt([x,y,z]));g.material=material('Graphite');g
    end
    def part_annotations(entities,p,transform,z,machining:true)
      ink=%w[Front Graphite Appliance].include?(p[:material]) ? 'Light' : 'Graphite'
      Annotations.layout(p,transform,machining:machining,detail:@job[:settings].fetch(:label_detail,'compact')).each do |a|
        category=case a[:kind];when 'MACHINING_LABEL' then 'Machining';when 'EDGEBAND_LABEL' then 'Edgebands';else 'Part numbers';end
        text_on_plane(entities,a[:text],a[:x],a[:y],z,a[:size],category,color:ink,width:a[:width])
      end
    end
    def add_cabinet(c,label:false)
      g=super
      walk(g) do |entity|
        raw=entity.get_attribute(S::DICT,'part')
        next unless raw
        p=JSON.parse(raw,symbolize_names:true)
        entity.layer=tag(p[:category]||'Carcass')
      end
      # Preview holes are on independent entities; hidden door faces can leave holes visible.
      g.entities.to_a.each { |e| retag_drilling(e) }
      c[:parts].each do |p|
        next if p[:kind]!='panel'
        mg=find_motion(g,p[:motion]); owner=mg ? mg.entities : g.entities
        grooves=p[:operations].select { |o| o[:kind]=='groove' }
        unless grooves.empty?
          marks=owner.add_group;marks.name="Grooves / #{p[:number]}";marks.layer=tag('Machining');marks.transformation=part_pose(p)
          grooves.each do |o|
            z=o[:face]=='A' ? -0.1 : p[:t]+0.1
            points=AJBoardKitchen.groove_outline(o)
            points.each_with_index { |a,i| marks.entities.add_line(pt([*a,z]),pt([*points[(i+1)%4],z])).material=material('Drilling') }
          end
        end
        labels=owner.add_group;labels.name="Labels / #{p[:number]} / #{p[:name]}";labels.transformation=part_pose(p)
        part_annotations(labels.entities,p,proc { |x,y| [x,y] },p[:t]+0.5,machining:false)
        # Both faces carry readable identification; one may be inside a cabinet.
        reverse=labels.entities.add_group;reverse.name="A-side labels / #{p[:number]}"
        reverse.transformation=Geom::Transformation.axes(pt([p[:w],0,-0.5]),vec([-1,0,0]),vec([0,1,0]),vec([0,0,-1]))
        part_annotations(reverse.entities,p,proc { |x,y| [x,y] },0,machining:false)
        edges=owner.add_group;edges.name="Band / #{p[:number]}";edges.layer=tag('Edgebands');edges.transformation=part_pose(p)
        AJBoardKitchen.edge_segments(p).each do |a,b,side,t|
          if %w[B T].include?(side)
            # Horizontal bands cover the corner ends of the vertical strips.
            a=a.dup;b=b.dup
            [a,b].each do |point|
              point[0]-=p[:edges].fetch('L',0) if point[0].abs<0.01
              point[0]+=p[:edges].fetch('R',0) if (point[0]-p[:w]).abs<0.01
            end
          end
          dx,dy=case side;when 'L' then [-t,0];when 'R' then [t,0];when 'B' then [0,-t];else [0,t];end
          poly=[a,b,[b[0]+dx,b[1]+dy],[a[0]+dx,a[1]+dy]]
          band=edges.entities.add_group;prism(band.entities,poly,[],p[:t]);band.material=material(p[:material])
        end
        edge_ops=p[:operations].select { |o| o[:face]=='EDGE' }
        unless edge_ops.empty?
          marks=owner.add_group;marks.name="Edge machining / #{p[:number]}";marks.layer=tag('Machining');marks.transformation=part_pose(p)
          edge_ops.each { |o| marks.entities.add_circle(pt([o[:edge]=='LEFT' ? -0.1 : p[:w]+0.1,o[:y],p[:t]/2]),X_AXIS,mm(o[:diameter]/2),16).each { |e| e.material=material('Drilling') } }
        end
      end
      g
    end
    def retag_drilling(entity)
      return unless entity.respond_to?(:definition)
      entity.layer=tag('Machining') if entity.name.start_with?('Drilling /')
      entity.definition.entities.each { |e| retag_drilling(e) }
    end
    def find_motion(g,id)
      return nil unless id
      found=nil
      walk(g) { |e| raw=e.get_attribute(S::DICT,'motion');found=e if raw && JSON.parse(raw)['id']==id }
      found
    end
    def add_hardware(entities,h)
      super
      entity=entities.to_a.last
      category=if h[:name]=~/hinge/i then 'Hinges'
               elsif h[:name]=~/runner|locking plate/i then 'Runners'
               elsif h[:name]=~/cam|bolt|screw|dowel|ovvo|rafix/i then 'Connectors'
               elsif h[:name]=~/foot/i then 'Plinth'
               else 'Appliances' end
      entity.layer=tag(category)
    end
    def build_test!
      started=false
      raise 'Exit the current component edit before building the test.' unless @model.active_path.nil?
      old=@model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'owned') && !g.get_attribute('LuxKTC','project_id') }
      others=@model.entities.to_a.reject { |e| old.include?(e) }
      maxx=others.select { |e| e.respond_to?(:bounds) && !e.bounds.empty? }.map { |e| e.bounds.max.x.to_f*25.4 }.max
      offset=old.empty? ? (maxx ? maxx+1000 : 0) : old.first.transformation.origin.x.to_f*25.4
      begin_build
      started=true
      @root.name="AJ | Board Gola kitchen | #{@job[:width].round(2)} mm | #{VERSION}";@root.set_attribute(DICT,'owned',true)
      @root.set_attribute(DICT,'job',JSON.generate(@job))
      @root.transformation=Geom::Transformation.translation(pt([offset,0,0]))
      @job[:cabinets].each { |c| add_cabinet(c) }
      @kitchen_bounds=@root.bounds
      nesting_start=[maxx||0,offset+@job[:width]].max+1000-offset
      draw_nesting(nesting_start)
      CATEGORIES.each { |cat| tag(cat).visible=true }
      old.each(&:erase!)
      finish_build
      focus_kitchen
      @root
    rescue StandardError=>e
      abort_build(e) if started
      raise
    end
    def draw_nesting(start_x)
      sheets=AJBoardKitchen.nest(@job);lookup=AJBoardKitchen.panels(@job).to_h { |p| [p[:number],p] }
      @nest_root=@root.entities.add_group;@nest_root.name='Nested sheets / no overlap';@nest_root.layer=tag('Nesting')
      @nest_root.set_attribute(DICT,'sheets',JSON.generate(sheets))
      sheets.each_with_index do |s,index|
        g=@nest_root.entities.add_group;g.name="#{s[:id]} / #{s[:material]} #{s[:t]} mm"
        sx=start_x+(index%3)*(s[:w]+350);sy=(index/3)*(s[:h]+350)
        g.transformation=Geom::Transformation.translation(pt([sx,sy,0]))
        border=S.rectangle(s[:w],s[:h]);border.each_with_index { |a,i| b=border[(i+1)%4];g.entities.add_line(pt([*a,0]),pt([*b,0])) }
        text_on_plane(g.entities,"#{s[:id]}  #{s[:material]} #{s[:t].to_i}mm",0,s[:h]+70,0,40,'Nesting')
        s[:placements].each do |at|
          p=lookup.fetch(at[:part]);piece=g.entities.add_group;piece.name="#{p[:number]} / #{p[:name]}"
          piece.set_attribute(DICT,'nested_part',p[:number]);piece.set_attribute(DICT,'sheet',s[:id])
          xy=proc { |x,y| AJBoardKitchen.place_xy(p,at,x,y) }
          outline=p[:outline].map { |x,y| xy.call(x,y) };holes=p[:holes].map { |poly| poly.map { |x,y| xy.call(x,y) } }
          prism(piece.entities,outline,holes,p[:t]);cut_grooves(piece.entities,p,xy);piece.material=material(p[:material])
          # Text groups live on the sheet, not the rotated part transform.
          part_annotations(g.entities,p,xy,p[:t]+0.6)
          marks=g.entities.add_group;marks.name="All machining / #{p[:number]}";marks.layer=tag('Machining')
          p[:operations].each do |o|
            xx,yy=xy.call(o[:x],o[:y]);z=p[:t]+0.3
            if o[:kind]=='groove'
              points=AJBoardKitchen.groove_outline(o).map { |x,y| xy.call(x,y) }
              points.each_with_index { |a,i| marks.entities.add_line(pt([*a,z]),pt([*points[(i+1)%4],z])).material=o[:face]=='A' ? material('Drilling') : material('Front') }
            elsif o[:face]=='EDGE'
              marks.entities.add_line(pt([xx-3,yy-3,z]),pt([xx+3,yy+3,z]))
              marks.entities.add_line(pt([xx-3,yy+3,z]),pt([xx+3,yy-3,z]))
            else
              edges=marks.entities.add_circle(pt([xx,yy,z]),Z_AXIS,mm(o[:diameter]/2),16)
              edges.each { |e| e.material=o[:face]=='A' ? material('Drilling') : material('Front') }
            end
          end
          bands=g.entities.add_group;bands.name="Banded sides / #{p[:number]}";bands.layer=tag('Edgebands')
          [0,4].each { |off| AJBoardKitchen.edge_segments(p,off).each { |a,b,_,_| bands.entities.add_line(pt([*xy.call(*a),p[:t]+0.4]),pt([*xy.call(*b),p[:t]+0.4])).material=material('Edgeband') } }
        end
      end
      @nest_root
    end
    def focus_kitchen
      b=Geom::BoundingBox.new
      @cabinet_entities.each { |g| b.add(g.bounds) }
      shift=@root.transformation.origin
      center=b.center.transform(@root.transformation)
      eye=center+Geom::Vector3d.new(mm(3000),mm(-5500),mm(2300))
      camera=Sketchup::Camera.new(eye,center,Z_AXIS,false)
      aspect=@model.active_view.vpwidth.to_f/[@model.active_view.vpheight,1].max
      camera.height=[mm(3200),mm(4100)/aspect].max
      @model.active_view.camera=camera;@model.active_view.refresh
    end
    def focus_nesting
      tag('Nesting').visible=true
      b=@nest_root.bounds;center=b.center.transform(@root.transformation)
      camera=Sketchup::Camera.new(center+Geom::Vector3d.new(0,0,mm(16000)),center,Y_AXIS,false)
      aspect=@model.active_view.vpwidth.to_f/[@model.active_view.vpheight,1].max
      camera.height=[(b.max.y-b.min.y)*1.08,(b.max.x-b.min.x)*1.08/aspect].max
      @model.active_view.camera=camera;@model.active_view.refresh
    end
  end

  def guard
    yield
  rescue StandardError=>e
    File.write(File.join(ROOT,'last_error.txt'),"#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
    update_status(e.message)
    UI.messagebox("AJ board test: #{e.message}");warn e.full_message
  end
  def build!(input=nil,preserve_camera:false)
    raise 'A shared LuxKTC project is active. Use Edit selected project cabinet or the web interface, then Push SketchUp edits.' if defined?(Sync) && Sync.active?
    conf=input || @config || DEFAULTS
    camera=Sketchup.active_model.active_view.camera if preserve_camera
    visibility=@view ? CATEGORIES.to_h { |cat| [cat,@view.tag(cat).visible?] } : {}
    job=make_job(conf);nest(job);view=View.new(job);view.build_test!
    @config=job[:settings];@job=job;@view=view
    @pending_edit=nil
    Sketchup.active_model.active_view.camera=camera if camera
    visibility.each { |cat,visible| view.tag(cat).visible=visible } if preserve_camera
    sync_dialog
    update_status('Kitchen rebuilt. Machining recipes are editable test values.')
    job
  end
  def active!
    raise 'Build the board test first.' unless @view && @view.root.valid? && @view.root.model==Sketchup.active_model
    @view
  end
  def toggle(category)
    view=active!;layer=view.tag(category);layer.visible=!layer.visible;Sketchup.active_model.active_view.refresh
  end
  def show_all
    view=active!;CATEGORIES.each { |cat| view.tag(cat).visible=true };Sketchup.active_model.active_view.refresh
  end
  def export!(base=nil)
    active!;base ||= UI.select_directory(title:'Choose folder for DXF, BOM and part stickers')
    return unless base
    folder=Export.package(@job,base)
    File.write(File.join(folder,'SketchUp_geometry_audit.json'),JSON.pretty_generate(@view.statistics))
    update_status("Exported #{AJBoardKitchen.panels(@job).size} panels: #{folder}")
    UI.messagebox("Export complete:\n#{folder}\n\nSketchUp: parts_dxf or sheets_dxf, with visible labels.\nAspire: aspire_dxf/parts or aspire_dxf/sheets; set job units to mm.\nOptional CAD TEXT files: cad_dxf/parts and cad_dxf/sheets.\nBOM.pdf, BOM.csv, Part_Stickers.pdf, Nested_Sheets.pdf and machining.csv are also included.")
    folder
  end
  def update_status(message)
    Sketchup.status_text="AJ Board: #{message}"
    @dialog.execute_script("showStatus(#{JSON.generate(message)})") if @dialog && @dialog.visible?
  end
  def show_dialog
    if @dialog && @dialog.visible?;@dialog.bring_to_front;return;end
    @dialog=UI::HtmlDialog.new(dialog_title:'AJ / Board kitchen test',preferences_key:'AJBoardKitchenTest',scrollable:true,resizable:true,width:610,height:760,style:UI::HtmlDialog::STYLE_DIALOG)
    @dialog.set_file(File.join(ROOT,'panel.html'))
    @dialog.add_action_callback('ready') { |_ctx| sync_dialog }
    @dialog.add_action_callback('build') { |_ctx,json| guard { build!(JSON.parse(json,symbolize_names:true)) } }
    @dialog.add_action_callback('toggle') { |_ctx,category| guard { toggle(category) } }
    @dialog.add_action_callback('all') { guard { show_all } }
    @dialog.add_action_callback('export') { guard { export! } }
    @dialog.add_action_callback('kitchen') { guard { active!.focus_kitchen } }
    @dialog.add_action_callback('sheets') { guard { active!.focus_nesting } }
    @dialog.add_action_callback('open') { guard { active!.animate(1.0) } }
    @dialog.add_action_callback('close') { guard { active!.animate(0.0) } }
    @dialog.add_action_callback('pickCabinet') { guard { pick_cabinet } }
    @dialog.add_action_callback('previewEdit') { |_ctx,json| guard { preview_cabinet_edit(JSON.parse(json,symbolize_names:true)) } }
    @dialog.add_action_callback('applyEdit') { guard { apply_cabinet_edit } }
    @dialog.add_action_callback('renest') { |_ctx,json| guard { renest!(json ? JSON.parse(json,symbolize_names:true) : {}) } }
    @dialog.show
  end
  def sync_dialog
    return unless @dialog && @dialog.visible?
    @dialog.execute_script("loadSettings(#{JSON.generate(@config||DEFAULTS)})")
    list=@job ? panels(@job).map { |p| p.slice(:id,:number,:name,:cabinet_id,:w,:h,:finished_w,:finished_h,:edges,:outline) } : []
    @dialog.execute_script("loadParts(#{JSON.generate(list)})")
    cabs=@job ? @job[:cabinets].reject { |c| c[:id]=='R01' }.map { |c| c.slice(:id,:name,:w,:h,:d,:pose,:width_locked,:width_anchor) } : []
    @dialog.execute_script("loadCabinets(#{JSON.generate(cabs)},#{JSON.generate(@config||DEFAULTS)},#{JSON.generate(VERSION)},#{JSON.generate(@editing_id)})")
  end
  def install_toolbar
    return if @toolbar && @toolbar_version==VERSION
    @toolbar.hide if @toolbar
    @toolbar_version=VERSION
    @toolbar=UI::Toolbar.new('AJ Board Kitchen')
    commands=[['Settings','settings',proc { show_dialog }],['Connectors','connectors',proc { toggle('Connectors') }],['Hinges','hinges',proc { toggle('Hinges') }],['Doors','doors',proc { toggle('Doors') }],['Drawer faces','faces',proc { toggle('Drawer faces') }],['Drawer boxes','boxes',proc { toggle('Drawer boxes') }],['Drill marks','drill',proc { toggle('Machining') }],['Edgebands','bands',proc { toggle('Edgebands') }],['Part numbers','labels',proc { toggle('Part numbers') }],['All visible','all',proc { show_all }],['Kitchen view','home',proc { active!.focus_kitchen }],['Nested sheets','sheets',proc { active!.focus_nesting }],['Export DXF + BOM + stickers','export',proc { export! }]]
    commands.insert(1,['Edit cabinet','edit',proc { pick_cabinet }])
    commands << ['Re-nest current parts','renest',proc { renest! }]
    commands.each do |label,icon,action|
      cmd=UI::Command.new(label) { guard { action.call } };cmd.tooltip=label;cmd.status_bar_text="AJ board test: #{label}"
      cmd.small_icon=File.join(ROOT,'assets',"#{icon}.png");cmd.large_icon=cmd.small_icon;@toolbar.add_item(cmd)
    end
    @toolbar.show
    return if @menu_installed
    @menu_installed=true
    menu=UI.menu('Extensions').add_submenu('AJ Board Kitchen Test')
    menu.add_item('Settings and visibility') { guard { show_dialog } }
    menu.add_item('Build / rebuild 10 foot test') { guard { build! } }
    menu.add_item('Export manufacturing review package') { guard { export! } }
    menu.add_item('Click / edit cabinet') { guard { pick_cabinet } }
    menu.add_item('Re-nest current parts') { guard { renest! } }
    UI.add_context_menu_handler do |context|
      id=cabinet_id_from((Sketchup.active_model.active_path||[])+Sketchup.active_model.selection.to_a)
      context.add_item("AJ: edit #{id}") { guard { edit_cabinet(id) } } if id
    end
  end
  def boot
    install_toolbar
    Sync.install if defined?(Sync)
    if defined?(Sync) && Sync.rehydrate
      update_status('Shared LuxKTC project restored. Pull web changes or push local parametric edits using the LuxKTC toolbar.')
    else
      update_status('LuxKTC ready. Pull a shared project, or explicitly build the 10 foot test from the AJ Board Kitchen menu.')
    end
    Studio.show if defined?(Studio)
  end
end
