require_relative '../export'
base=AJBoardKitchen::ROOT
folder=File.join(base,'example_export')
job=JSON.parse(File.read(File.join(folder,'job.json')),symbolize_names:true)
# JSON symbolization affects band-side hash keys; restore the exporter contract.
AJBoardKitchen.panels(job).each { |p| p[:edges]=p[:edges].transform_keys(&:to_s) }
sheets=JSON.parse(File.read(File.join(folder,'nesting.json')),symbolize_names:true)
job[:version]=AJBoardKitchen::VERSION
panels=AJBoardKitchen.panels(job)
detail=job[:settings].fetch(:label_detail,'compact')
AJBoardKitchen::Export.dxf_sets(folder,panels,sheets,label_detail:detail) unless ARGV.include?('--samples-only')
File.write(File.join(folder,'job.json'),JSON.pretty_generate(job))
AJBoardKitchen::Export.machining_csv(File.join(folder,'machining.csv'),AJBoardKitchen.parts(job))
samples=File.expand_path('../DXF_Import_Test',base)
FileUtils.mkdir_p(samples)
d=AJBoardKitchen::DXF.new
d.poly(AJBoardScaffold.rectangle(100,100))
d.circle(50,50,10,'DRILL_TEST')
d.save(File.join(samples,'01_Calibration_100mm.dxf'))
FileUtils.cp(File.join(folder,'parts_dxf','P001_B.dxf'),File.join(samples,'02_P001_BackGroove_B.dxf'))
FileUtils.cp(File.join(folder,'sheets_dxf','S06_A.dxf'),File.join(samples,'03_S06_Nested_A.dxf'))
FileUtils.cp(File.join(folder,'sketchup_dxf','parts','P001_B.dxf'),File.join(samples,'04_P001_B_VISIBLE_LABELS.dxf'))
hinge=panels.find { |p| p[:operations].any? { |o| o[:recipe]=='review-cup35' } }
FileUtils.cp(File.join(folder,'sketchup_dxf','parts',"#{hinge[:number]}_A.dxf"),File.join(samples,'05_HINGE_DOOR_VISIBLE_LABELS.dxf'))
FileUtils.cp(File.join(folder,'sketchup_dxf','sheets','S06_A.dxf'),File.join(samples,'06_NESTED_VISIBLE_LABELS.dxf'))
ad=AJBoardKitchen::AspireDXF.new(sketchup_labels:true)
ad.poly(AJBoardScaffold.rectangle(100,100),'CUT_A_OUTSIDE_Z18p0')
ad.circle(25,25,2.5,'REVIEW_A_DRILL_D5p0_Z12p0')
ad.circle(70,25,17.5,'REVIEW_A_POCKET_D35p0_Z13p0')
ad.poly([[10,70],[90,70],[90,76],[10,76]],'REVIEW_A_GROOVE_W6p0_Z5p0')
ad.text('100 X 100 MM',10,85,5,'PART_SIZE')
ad.save(File.join(samples,'07_ASPIRE_100mm_LAYER_TEST.dxf'))
FileUtils.cp(File.join(folder,'aspire_dxf','parts',"#{hinge[:number]}_A.dxf"),File.join(samples,'08_ASPIRE_HINGE_DOOR.dxf'))
FileUtils.cp(File.join(folder,'aspire_dxf','sheets','S06_A.dxf'),File.join(samples,'09_ASPIRE_NESTED_S06_A.dxf'))
File.write(File.join(samples,'IMPORT.txt'),"AutoCAD 2000 DXFs. SketchUp: File > Import > AutoCAD Files. Options: Millimeters.\nThe calibration square is 100 x 100 mm with a 20 mm diameter circle.\nAll part/sheet samples 02 through 06 include VISIBLE LINE LABELS on NONCUT_LABEL_* layers.\n01 is calibration. Optional real CAD TEXT files are in app/example_export/cad_dxf.\nAll labelled panels/sheets: app/example_export/parts_dxf and sheets_dxf.\nNONCUT_LABEL_* is review lettering, never a machining toolpath.\n")
File.open(File.join(samples,'IMPORT.txt'),'a') do |f|
  f.puts "\nASPIRE: Set job to millimetres. Import 07_ASPIRE_100mm_LAYER_TEST.dxf first: verify the square is 100 x 100 mm and drill/pocket/groove/cut are separate layers. Samples 08/09 are real part/nest files. All Aspire R12 exports: app/example_export/aspire_dxf/parts and sheets. Exclude NONCUT layers from machining."
end
puts "Regenerated #{panels.size} panels and #{sheets.size} sheets. Import samples: #{samples}"
