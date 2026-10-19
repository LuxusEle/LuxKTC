# frozen_string_literal: true
# Load this file in SketchUp's Ruby Console. No extension installation required.
require 'sketchup.rb' if defined?(Sketchup)
# Explicit load refreshes a development revision in an already-open SketchUp.
if defined?(AJBoardKitchen)
  old_dialog=AJBoardKitchen.instance_variable_get(:@dialog)
  old_dialog.close if old_dialog
  AJBoardKitchen.instance_variable_set(:@dialog,nil)
  if defined?(AJBoardKitchen::Studio)
    studio_dialog=AJBoardKitchen::Studio.instance_variable_get(:@dialog)
    studio_dialog.close if studio_dialog
    AJBoardKitchen::Studio.instance_variable_set(:@dialog,nil)
  end
end
%w[vendor/master_scaffold layout engineering annotations export view editor project_bridge sync project_ui].each { |file| load File.join(__dir__,file+'.rb') }
puts "AJ Board Kitchen #{AJBoardKitchen::VERSION} loaded. Main DXFs include visible LINE labels."
AJBoardKitchen.guard { AJBoardKitchen.boot } if defined?(Sketchup::Model) && defined?(UI)
