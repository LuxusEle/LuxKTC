# frozen_string_literal: true
# Exercise the real Studio controller and board engine with only native UI/I/O
# boundaries mocked. Never opens or changes an installed SketchUp model.
require_relative '../engineering'
require_relative '../view'
require_relative '../project_ui'

def check(value, message); raise message unless value; end

class StudioModel
  def layers; {}; end
end
module Sketchup
  class << self
    attr_writer :test_model
    def active_model; @test_model ||= StudioModel.new; end
  end
end
class StudioRoot
  def valid?; true; end
  def model; Sketchup.active_model; end
end
module UI
  class HtmlDialog
    STYLE_DIALOG = 0
    attr_reader :options, :file, :scripts, :callbacks
    def initialize(**options); @options=options; @scripts=[]; @callbacks={}; end
    def add_action_callback(name,&callback); @callbacks[name]=callback; end
    def set_on_closed(&block); @closed=block; end
    def set_file(file); @file=file; end
    def show; true; end
    def bring_to_front; true; end
    def execute_script(code); @scripts << code; end
    def close; @closed.call; end
  end
  def self.openURL(url); @url=url; end
end
module AJBoardKitchen::Sync
  class << self
    attr_accessor :test_requests, :test_remote, :test_moves, :test_builds, :test_cancel
    def server; 'http://127.0.0.1:8740'; end
    def request(method,path,body=nil,on_error:nil,&success)
      @test_requests ||= []
      @test_requests << {method:method,path:path,body:body,error:on_error,success:success}
    end
    def reply(data)
      row=@test_requests.shift; raise 'No queued request' unless row
      row[:success].call(AJBoardKitchen::ProjectBridge.copy(data),nil)
      row
    end
    def active?; !!@project; end
    def persist; end
    def capture_positions(project)
      project[:design][:cabinets].each do |cab|
        cab.merge!(@test_moves.fetch(cab[:id],{})) if @test_moves
      end
      project
    end
    def apply_project(project,dirty:false,preserve_camera:false)
      raise 'Studio rebuild changed the camera' unless preserve_camera
      @test_builds=(@test_builds || 0)+1
      generated=AJBoardKitchen::ProjectBridge.generate(project)
      AJBoardKitchen.instance_variable_set(:@job,generated[:job])
      @project=AJBoardKitchen::ProjectBridge.copy(project)
      @root=StudioRoot.new; @dirty=dirty; @change_serial=(@change_serial || 0)+1
      generated
    end
    def pull(id=nil,on_success:nil,on_error:nil)
      if @test_cancel
        on_error.call('Pull cancelled',0,{cancelled:true}); return
      end
      apply_project(@test_remote.fetch(id),dirty:false,preserve_camera:true)
      on_success.call(@project)
    end
    def push(on_success:nil,on_error:nil)
      @dirty=true;@change_serial=(@change_serial || 0)+1
      generated=AJBoardKitchen::ProjectBridge.generate(@project)
      request(:put,"/api/projects/#{@project[:id]}",{base_revision:@project[:revision],project:@project,generated:generated},on_error:on_error) do |saved,_|
        @project=saved;@dirty=false;on_success.call(saved)
      end
    end
  end
end

studio=AJBoardKitchen::Studio
sync=AJBoardKitchen::Sync
dialog=studio.show
check(File.file?(dialog.file) && File.basename(dialog.file)=='studio.html','Studio did not load its own local UI')
check(dialog.callbacks.key?('luxktc_action'),'Ruby bridge callback missing')
check(dialog.options[:dialog_title]=='LuxKTC Project Studio','Native dialog not identified')
studio.handle(action:'ready')
check(studio.snapshot[:busy],'Ready request did not mark busy')
sync.reply([])
sync.reply(studio.fallback_catalog)
check(!studio.snapshot[:busy] && dialog.scripts.any? { |script| script.include?('LuxKTCStudio.receive') },'Initial callback did not render or finish')

empty={schema_version:1,id:'studio-project',name:'Studio-created kitchen',client:'',revision:1,
  room:{walls:[]},design:{style:'modern_gola',settings:AJBoardKitchen.settings,accessories:{worktops:false,end_scribe_mm:0},cabinets:[]},
  quote:{currency:'LKR',rates:{},labour:0,markup_pct:0,tax_pct:0},manufacturing:{}}
sync.test_remote={empty[:id]=>empty}
studio.handle(action:'create',payload:{name:empty[:name],template:'empty'})
check(sync.test_requests.first[:method]==:post,'Native project creation did not use shared API')
sync.reply(empty)
check(studio.snapshot[:project][:id]==empty[:id] && !studio.snapshot[:busy],'Created project did not open in native studio')

candidate=AJBoardKitchen::ProjectBridge.copy(studio.snapshot[:project])
candidate[:room][:walls]=[{id:'measured-wall',name:'Wall without photo',width_mm:3000,height_mm:2600,thickness_mm:150,
  origin_mm:[0,0,0],rotation_deg:0,measurements_confirmed:true,openings:[]}]
candidate[:design][:cabinets]=[{id:'cabinet-uuid',local_id:'B01',name:'Door unit',type:'base_single',wall_id:'measured-wall',
  width_mm:600,height_mm:720,depth_mm:560,x_mm:0,y_mm:0,z_mm:0,rotation_deg:0,options:{}}]
studio.handle(action:'apply',payload:{project:candidate,base_model_serial:studio.model_serial})
check(studio.snapshot[:error].nil? && !studio.snapshot[:busy],'Photo-free apply failed')
check(studio.snapshot[:project][:room][:walls].first[:photo_asset_id].nil?,'Photo became mandatory')
check(AJBoardKitchen.instance_variable_get(:@job)[:cabinets].first[:parts].any? { |part| part[:name]=='Back (grooved)' },'Native UI bypassed corrected board engine')
check(studio.snapshot[:dirty],'Local model build was incorrectly marked saved')
no_photo_done=false
before_requests=sync.test_requests.length
sync.download_textures(studio.snapshot[:project]) { no_photo_done=true }
check(no_photo_done && sync.test_requests.length==before_requests,'Image-free wall attempted a texture download')

measured_wall=sync.project[:room][:walls].first
measured_wall.merge!(photo_asset_id:'original-photo',rectified_asset_id:'old-texture',annotated_asset_id:'old-measurements',photo_quad:[[0,0],[300,0],[300,260],[0,260]],
  rectification:{source_asset_id:'original-photo',width_mm:3000,height_mm:2600,quad:[[0,0],[300,0],[300,260],[0,260]]})
resurveyed=AJBoardKitchen::ProjectBridge.copy(sync.project)
resurveyed[:room][:walls].first[:width_mm]=3200
prepared=studio.prepare_project(project:resurveyed,base_model_serial:studio.model_serial)
check(prepared[:room][:walls].first[:rectified_asset_id].nil? && measured_wall[:rectified_asset_id]=='old-texture','Native wall dimension change reused a stale texture or mutated input')
%i[photo_asset_id rectified_asset_id annotated_asset_id photo_quad rectification].each { |key| measured_wall.delete(key) }

# A report previews the submitted form without rebuilding or persisting it.
preview=AJBoardKitchen::ProjectBridge.copy(studio.snapshot[:project])
preview[:quote][:labour]=500
builds=sync.test_builds
studio.handle(action:'report',payload:{project:preview,base_model_serial:studio.model_serial})
queued=sync.test_requests.first
check(queued[:path]=='/api/preview' && queued[:body][:generated][:job][:input_manifest][:design]==preview[:design],'Preview did not use the same generated input')
sync.reply(bom:{preview:true,parts:[]},quote:{preview:true,total:500})
check(sync.test_builds==builds && sync.project[:quote][:labour]==0,'BOM preview changed model or applied form')
check(!studio.snapshot[:busy],'Preview did not release controls')

# Capture native moves without overwriting independent form dimensions.
sync.test_moves={'cabinet-uuid'=>{x_mm:100}}
edited=AJBoardKitchen::ProjectBridge.copy(sync.project)
edited[:design][:cabinets].first[:height_mm]=760
studio.handle(action:'apply',payload:{project:edited,base_model_serial:studio.model_serial})
check(sync.project[:design][:cabinets].first.values_at(:x_mm,:height_mm)==[100,760],'Native placement or form dimensions lost')
sync.test_moves={'cabinet-uuid'=>{x_mm:200}}
conflicting=AJBoardKitchen::ProjectBridge.copy(sync.project)
conflicting[:design][:cabinets].first[:x_mm]=150
studio.handle(action:'apply',payload:{project:conflicting,base_model_serial:studio.model_serial})
check(studio.snapshot[:error].include?('two different') && sync.project[:design][:cabinets].first[:x_mm]==100,'Dual edit was silently overwritten')
sync.test_moves={}

# Failed saves release controls, preserve the draft, and permit a corrected retry.
outgoing=AJBoardKitchen::ProjectBridge.copy(sync.project)
original_serial=studio.model_serial
studio.handle(action:'save',payload:{project:outgoing,base_model_serial:original_serial})
failed=sync.test_requests.shift
failed[:error].call('Validation failed',422,{})
check(!studio.snapshot[:busy] && studio.snapshot[:error]=='Validation failed' && sync.instance_variable_get(:@dirty),'Failed save lost model edits or locked the UI')
outgoing[:client]='Corrected after failure'
studio.handle(action:'save',payload:{project:outgoing,base_model_serial:original_serial})
check(sync.test_requests.length==1 && studio.snapshot[:busy],'Corrected retry falsely rejected its own changed model serial')
saved=AJBoardKitchen::ProjectBridge.copy(sync.project);saved[:revision]=2
sync.reply(saved)
check(studio.snapshot[:project][:revision]==2 && !studio.snapshot[:busy] && !studio.snapshot[:dirty],'Successful save did not update native project')

# An independently changed model serial remains a hard stale-form conflict.
stale=AJBoardKitchen::ProjectBridge.copy(sync.project)
studio.handle(action:'apply',payload:{project:stale,base_model_serial:studio.model_serial-1})
check(studio.snapshot[:error].include?('predates another'),'Stale model form was accepted')
sync.test_cancel=true
studio.handle(action:'pull')
check(!studio.snapshot[:busy] && studio.snapshot[:error].nil? && studio.snapshot[:message]=='Pull cancelled','Cancelled pull locked the studio')
sync.test_cancel=false

# A delayed response cannot alter the wrong active SketchUp model.
studio.handle(action:'list')
Sketchup.test_model=StudioModel.new
sync.reply([])
check(!studio.snapshot[:busy] && studio.snapshot[:error].include?('model changed'),'Stale model callback was applied')

# Closing the panel cancels its old UI context; re-opening can initialize again.
studio.handle(action:'list')
dialog.close
check(!studio.instance_variable_get(:@busy),'Closing the dialog kept its editor locked')
new_dialog=studio.show
studio.handle(action:'ready')
old=sync.test_requests.shift
old[:success].call([],nil)
check(studio.snapshot[:busy],'Old dialog callback completed a new dialog operation')
sync.reply([]);sync.reply(studio.fallback_catalog)
check(!studio.snapshot[:busy] && new_dialog!=dialog,'Reopened panel did not initialize')

puts JSON.pretty_generate(passed:true,checks:['Independent local HtmlDialog and Ruby callbacks','Create project through shared API',
  'Walls and corrected-engine cabinets without photos','No image download for plain measured walls',
  'Unsaved BOM/quote preview without model/database writes','Native moves merge with independent form edits',
  'Conflicting/stale edits retained','Failed save permits a corrected retry','Cancellation and model-context guards',
  'Closed/reopened dialog ignores stale callbacks'])
