require_relative '../export'
job=AJBoardKitchen.make_job
folder=AJBoardKitchen::Export.package(job,File.join(AJBoardKitchen::ROOT,'test_output'))
puts JSON.pretty_generate(version:job[:version],export_folder:folder)
