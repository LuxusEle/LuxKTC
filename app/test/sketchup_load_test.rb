# Executed by SketchUp -RubyStartup. No existing user document is opened or saved.
require 'json'
require 'fileutils'
base=File.expand_path('..',__dir__)
out=File.join(base,'live_test');FileUtils.mkdir_p(out)
File.write(File.join(out,'startup_seen.txt'),Time.now.to_s)
UI.start_timer(3,false) do
  begin
    load File.join(base,'aj_board_kitchen.rb')
    app=AJBoardKitchen;view=app.active!;m=Sketchup.active_model
    report={runtime:RUBY_DESCRIPTION,sketchup:Sketchup.version,statistics:view.statistics,checks:[]}
    raise 'Part solids failed' unless view.statistics[:non_solid].empty?
    report[:checks]<<'All assembled board and profile components are closed solids'
    # Compare native solid volumes with the engineering groove removal.
    groove_count=0
    view.walk(view.root) do |entity|
      raw=entity.get_attribute(AJBoardScaffold::DICT,'part')
      next unless raw
      part=JSON.parse(raw,symbolize_names:true)
      grooves=part[:operations].select { |o| o[:kind]=='groove' }
      next if grooves.empty?
      area=AJBoardScaffold::Math3.area(part[:outline])-part[:holes].sum { |h| AJBoardScaffold::Math3.area(h) }
      expected=area*part[:t]-grooves.sum { |o| o[:w]*o[:h]*o[:depth] }
      measured=entity.volume*25.4**3
      raise "Groove volume mismatch #{part[:id]}" unless (measured-expected).abs<0.1
      groove_count+=grooves.size
    end
    raise 'Missing groove solids' unless groove_count==36
    report[:checks]<<'All 36 groove cuts match native solid volume'
    view.nest_root.entities.each do |sheet|
      next unless sheet.respond_to?(:entities)
      sheet.entities.each do |piece|
        next unless piece.get_attribute(app::DICT,'nested_part')
        raise 'Nested panel is not a solid' unless piece.manifold?
      end
    end
    report[:checks]<<'Nested panels are closed solids'
    view.animate(1.0);view.animate(0.0)
    report[:checks]<<'Doors and drawer motions opened and returned'
    %w[Connectors Hinges Doors].each { |cat| app.toggle(cat);app.toggle(cat) }
    report[:checks]<<'Visibility toggles exercised'
    # Root export saves only this prototype, rather than the entire active document.
    saved=view.root.definition.save_as(File.join(out,'AJ_10ft_Board_Kitchen.skp'))
    raise 'SKP save failed' unless saved
    report[:checks]<<'Prototype saved as standalone SKP'
    view.focus_kitchen
    m.rendering_options['BackgroundColor']=Sketchup::Color.new(245,244,239)
    m.rendering_options['DisplaySky']=false;m.rendering_options['DisplayGround']=false
    m.active_view.write_image(filename:File.join(out,'Kitchen.png'),width:1600,height:1000,antialias:true)
    view.focus_nesting
    m.active_view.write_image(filename:File.join(out,'Nested_Sheets.png'),width:1600,height:1000,antialias:true)
    view.focus_kitchen
    report[:export]=app::Export.package(view.job,out)
    File.write(File.join(out,'PASS.json'),JSON.pretty_generate(report))
  rescue Exception=>e
    File.write(File.join(out,'FAIL.txt'),"#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
  end
end
