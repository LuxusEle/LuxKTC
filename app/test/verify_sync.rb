# frozen_string_literal: true
require_relative '../project_bridge'

def check(condition, message); raise message unless condition; end
def rejects(message)
  begin
    yield
  rescue StandardError
    return
  end
  raise "Accepted invalid project: #{message}"
end
wall = {id: 'wall-a', width_mm: 6000, height_mm: 2600, thickness_mm: 150, origin_mm: [100,200,0], rotation_deg: 90, measurements_confirmed: true, openings: []}
families = AJBoardKitchen::ProjectBridge::TYPES
specs = families.each_with_index.map do |type, index|
  upper = type.start_with?('wall_'); tall = type.start_with?('tall_')
  {id: "cabinet-#{index}", local_id: format('%s%02d', upper ? 'W' : 'B', index+1), type: type, wall_id: wall[:id],
    width_mm: 600, height_mm: tall ? 2100 : upper ? 600 : 720, depth_mm: upper ? 330 : 580,
    x_mm: index*650, y_mm: 0, z_mm: upper ? 1600 : 0, rotation_deg: 0, options: {}}
end
project = {schema_version: 1, id: 'project-test', name: 'Shared project regression', revision: 3,
  room: {walls: [wall]}, design: {style: 'modern_gola', settings: {edge: 2, front_edge: 2}, cabinets: specs}, manufacturing: {}}
original = JSON.generate(project)
generated = AJBoardKitchen::ProjectBridge.generate(project)
job = generated[:job]
check(JSON.generate(project) == original, 'Generation mutated design input')
check(job[:cabinets].size == specs.size, 'Cabinet CRUD list was replaced by demo template')
job[:cabinets].zip(specs).each do |cab, spec|
  check(cab[:uuid] == spec[:id] && cab[:id] == spec[:local_id] && cab[:type] == spec[:type], 'Stable cabinet identities/types')
  check((cab[:pose][0]-100).abs < 0.001 && (cab[:pose][1]-200-spec[:x_mm]).abs < 0.001 && cab[:pose][3] == 90, 'Wall-relative placement')
  panels = cab[:parts].select { |part| part[:kind] == 'panel' }
  check(panels.any? { |part| part[:name].include?('stretcher') }, 'Missing structural rear stretchers')
  unless spec[:type] == 'base_sink'
    check(panels.any? { |part| part[:name] == 'Back (grooved)' }, 'Missing grooved back')
    check(panels.flat_map { |part| part[:operations] }.any? { |op| op[:kind] == 'groove' }, 'Missing back grooves')
  end
  panels.each do |part|
    edge = part[:edges]
    check((part[:w]+edge.fetch('L',0)+edge.fetch('R',0)-part[:finished_w]).abs < 0.001, 'Core width lost bands')
    check((part[:h]+edge.fetch('B',0)+edge.fetch('T',0)-part[:finished_h]).abs < 0.001, 'Core height lost bands')
  end
  check(cab[:parts].none? { |part| part[:section] == 'handle' }, 'Legacy door handle artifact returned')
end
old = job[:cabinets].flat_map { |cab| cab[:parts] }.to_h { |part| [part[:uuid],part[:number]] }
project[:manufacturing] = {job: job, nesting: generated[:nesting]}
project[:design][:cabinets].reverse!
project[:design][:cabinets].first[:width_mm] = 650
again = AJBoardKitchen::ProjectBridge.generate(project)
check(again[:job][:cabinets].flat_map { |cab| cab[:parts] }.all? { |part| old[part[:uuid]] == part[:number] }, 'Reorder/resize changed IDs or numbers')
# A B05 ordinary cupboard must not silently turn into the hob recipe.
ordinary = AJBoardKitchen::ProjectBridge.copy(project)
ordinary[:design][:cabinets] = [{id: 'ordinary', local_id: 'B05', wall_id: wall[:id], type: 'base_single', width_mm: 600, height_mm: 720, depth_mm: 580, options: {}}]
check(AJBoardKitchen.project_job(ordinary)[:cabinets].first[:hardware].none? { |hw| hw[:name] == 'Hob glass' }, 'Legacy ID changed semantic cabinet type')
ordinary[:design][:cabinets].first[:type] = 'base_gola'
ordinary[:design][:cabinets].first[:options][:role] = 'hob'
check(AJBoardKitchen.project_job(ordinary)[:cabinets].first[:hardware].any? { |hw| hw[:name] == 'Hob glass' }, 'Semantic hob role ignored')
rejects('lower open rack') { bad = AJBoardKitchen::ProjectBridge.copy(ordinary); bad[:design][:cabinets].first[:type] = 'base_open'; AJBoardKitchen.project_job(bad) }
rejects('missing wall') { bad = AJBoardKitchen::ProjectBridge.copy(ordinary); bad[:room][:walls] = []; AJBoardKitchen.project_job(bad) }
rejects('narrow oven tower') { bad = AJBoardKitchen::ProjectBridge.copy(ordinary); bad[:design][:cabinets].first.merge!(type:'tall_oven_micro',width_mm:450,height_mm:2100,options:{}); AJBoardKitchen.project_job(bad) }
rejects('hob on arbitrary cabinet') { bad = AJBoardKitchen::ProjectBridge.copy(ordinary); bad[:design][:cabinets].first[:type] = 'base_single'; AJBoardKitchen.project_job(bad) }
template = AJBoardKitchen::ProjectBridge.copy(project)
template[:room][:walls] = [{id:'template-wall',width_mm:3048,height_mm:2600,origin_mm:[0,0,0],rotation_deg:0}]
base,upper = AJBoardKitchen::Layout.specs(AJBoardKitchen.settings)
template[:design][:settings] = {}
template[:design][:accessories] = {worktops:true,end_scribe_mm:24}
template[:design][:cabinets] = (base+upper).map do |row|
  {id:"template-#{row[:id]}",local_id:row[:id],wall_id:'template-wall',type:row[:type],width_mm:row[:w],height_mm:row[:h],depth_mm:row[:d],x_mm:row[:x],y_mm:0,z_mm:row[:z],rotation_deg:0,options:row[:id]=='B05' ? {role:'hob'} : {}}
end
accessories = AJBoardKitchen.project_job(template)[:cabinets].select { |cab| cab[:accessory] }.flat_map { |cab| cab[:parts] }
top = accessories.find { |part| part[:material] == 'Worktop' }
check(top && top[:w] == 1974 && top[:h] == 620 && top[:t] == 30 && top[:holes].length == 2,'10ft worktop/cutouts dropped or changed')
check(accessories.count { |part| part[:name].include?('scribe') && part[:w] == 24 } == 2,'Explicit end scribes dropped')
rejects('end scribe outside measured wall') { bad = AJBoardKitchen::ProjectBridge.copy(template); bad[:room][:walls].first[:width_mm] = 3000; AJBoardKitchen.project_job(bad) }
# Exercise request retention and conflict preservation without a live network
# or model. These are the data-loss boundaries of the SketchUp bridge.
require_relative '../view'
require_relative '../sync'
module Sketchup
  def self.read_default(_group,_key,default); default; end
  def self.active_model; @model ||= Object.new; end
  module Http
    GET = 1; PUT = 2; POST = 3; DELETE = 4
    class Request
      attr_accessor :headers,:body
      def initialize(url,verb); @url=url; @verb=verb; end
      def start(&callback); @callback=callback; end
      def finish(status,body); @callback.call(self,Struct.new(:status_code,:body).new(status,JSON.generate(body))); end
      def finish_raw(status,body); @callback.call(self,Struct.new(:status_code,:body).new(status,body)); end
      def disconnect; @callback.call(self,nil); end
    end
  end
end
module UI
  def self.messagebox(*arguments); @last_message=arguments; 7; end
  def self.last_message; @last_message; end
end
module AJBoardKitchen
  def self.guard; yield; end
  def self.update_status(_message); end
end
class SyncRoot
  attr_reader :attributes
  def initialize; @attributes={}; end
  def valid?; true; end
  def model; Sketchup.active_model; end
  def set_attribute(dict,key,value); @attributes[[dict,key]]=value; end
end
sync = AJBoardKitchen::Sync
check(sync.checked_server('http://127.0.0.1:8740/') == 'http://127.0.0.1:8740','Loopback server normalization')
rejects('remote server') { sync.checked_server('https://example.com') }
rejects('embedded server credentials') { sync.checked_server('http://user:pass@127.0.0.1:8740') }
rejects('asset path traversal') { sync.safe_id('../outside') }
local = {id:'project-test',name:'Unsent SketchUp edits',revision:3}
root = SyncRoot.new
sync.instance_variable_set(:@project,local)
sync.instance_variable_set(:@root,root)
sync.request(:put,'/api/projects/project-test',{base_revision:3,project:local}) { raise 'Conflict unexpectedly treated as a success' }
pending = sync.instance_variable_get(:@requests)
check(pending.length == 1,'Async HTTP request not retained')
pending.values.first.finish(409,{detail:'Conflict',current_revision:4,current:{id:'project-test',name:'Web edits',revision:4}})
check(sync.project == local && sync.project[:revision] == 3 && sync.project[:name] == 'Unsent SketchUp edits','Conflict overwrote local project')
check(root.attributes[[sync::DICT,'dirty']] == true,'Conflict did not persist dirty project')
check(sync.instance_variable_get(:@requests).empty?,'Finished HTTP request was not released')
failures=[]; handler=proc { |message,code,data| failures << [message,code,data] }
created=nil
post=sync.request(:post,'/api/projects',{name:'Studio project'},on_error:handler) { |data,_response| created=data }
post.finish(201,{id:'created-project'})
check(created[:id]=='created-project' && failures.empty?,'POST success did not complete')
deleted=false
sync.request(:delete,'/api/projects/created-project',on_error:handler) { deleted=true }.finish_raw(204,'')
check(deleted,'DELETE empty success did not complete')
sync.request(:get,'/api/projects',on_error:handler).disconnect
sync.request(:get,'/api/projects/missing',on_error:handler).finish(404,{detail:'Not found'})
sync.request(:get,'/api/projects',on_error:handler).finish_raw(200,'not JSON')
sync.request(:get,'/api/projects',on_error:handler) { raise 'Model callback failed' }.finish(200,{projects:[]})
sync.request(:post,'invalid route',{},on_error:handler)
check(failures.length==5 && failures.map { |row| row[1] }==[0,404,200,200,0],'Transport, HTTP, parse, model-callback or setup errors failed to complete once')
check(failures[3][0]=='Model callback failed' && sync.instance_variable_get(:@requests).empty?,'Callback error leaked a retained request')
old_request=sync.request(:put,'/api/projects/project-test',{},on_error:handler)
sync.instance_variable_set(:@project,{id:'other-project',revision:1})
sync.instance_variable_set(:@dirty,false)
old_request.finish(409,{current_revision:4})
check(!sync.instance_variable_get(:@dirty),'Stale conflict marked a different active project dirty')
texture_errors=[]
sync.download_textures({room:{walls:[{rectified_asset_id:'sync-test-missing-asset-8740'}]}},on_error:proc { |*error| texture_errors << error }) { raise 'Missing asset unexpectedly completed' }
sync.instance_variable_get(:@requests).values.first.finish(404,{detail:'Missing asset'})
check(texture_errors.length==1 && texture_errors.first[1]==404,'Nested texture failure did not complete its caller')
sync.instance_variable_set(:@project,local)
class TestVector < Struct.new(:x,:y,:z)
  def to_a; [x,y,z]; end
  def length; Math.sqrt(x*x+y*y+z*z); end
  def dot(other); x*other.x+y*other.y+z*other.z; end
  def cross(other); TestVector.new(y*other.z-z*other.y,z*other.x-x*other.z,x*other.y-y*other.x); end
end
class TestTransform
  attr_accessor :origin,:xaxis,:yaxis,:zaxis
  def initialize
    @origin=TestVector.new(0,0,0); @xaxis=TestVector.new(1,0,0); @yaxis=TestVector.new(0,1,0); @zaxis=TestVector.new(0,0,1)
  end
  def to_a; [*xaxis.to_a,0,*yaxis.to_a,0,*zaxis.to_a,0,*origin.to_a,1]; end
end
class SceneNode
  attr_accessor :transformation,:material,:children
  def initialize; @transformation=TestTransform.new; @children=[]; @attrs={}; end
  def get_attribute(dict,key,default=nil); @attrs.fetch([dict,key],default); end
  def set_attribute(dict,key,value); @attrs[[dict,key]]=value; end
  def definition; Struct.new(:entities).new(children); end
  def name; 'Cabinet'; end
  def valid?; true; end
  def model; Sketchup.active_model; end
end
class SceneView < Struct.new(:cabinet_entities)
  def walk(entity,&block); block.call(entity); entity.children.each { |child| walk(child,&block) }; end
end
Z_AXIS=TestVector.new(0,0,1) unless defined?(Z_AXIS)
scene_root=SceneNode.new; cabinet=SceneNode.new; scene_root.children=[cabinet]
cabinet.set_attribute(AJBoardScaffold::DICT,'kind','cabinet'); cabinet.set_attribute(AJBoardScaffold::DICT,'id','B01')
cabinet.set_attribute(sync::DICT,'geometry_signature',sync.geometry_signature(cabinet))
scene_project={id:'scene-project',revision:1,room:{walls:[{id:'wall',origin_mm:[0,0,0],rotation_deg:0}]},design:{cabinets:[{id:'cabinet',local_id:'B01',wall_id:'wall',x_mm:0,y_mm:0,z_mm:0,rotation_deg:0}]}}
sync.instance_variable_set(:@root,scene_root); sync.instance_variable_set(:@project,scene_project)
AJBoardKitchen.instance_variable_set(:@view,SceneView.new([cabinet]))
cabinet.transformation.origin.x=100.0/25.4
captured=sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project))
check(captured[:design][:cabinets].first[:x_mm]==100,'Native cabinet move was lost')
scene_root.transformation.origin.x=1
rejects('native project-root move') { sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project)) }
scene_root.transformation.origin.x=0
cabinet.transformation.xaxis.x=-1
rejects('mirrored cabinet') { sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project)) }
cabinet.transformation.xaxis.x=1; cabinet.transformation.zaxis.z=-1
rejects('upside-down cabinet') { sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project)) }
cabinet.transformation.zaxis.z=1
cabinet.children << SceneNode.new
rejects('unsupported native geometry edit') { sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project)) }
cabinet.children.clear
scene_root.children << SceneNode.new
scene_root.children.last.set_attribute(AJBoardScaffold::DICT,'kind','cabinet')
rejects('untracked native cabinet copy') { sync.capture_positions(AJBoardKitchen::ProjectBridge.copy(scene_project)) }
scene_root.children.pop
MB_YESNO=4 unless defined?(MB_YESNO)
IDYES=6 unless defined?(IDYES)
sync.instance_variable_set(:@dirty,false)
sync.pull('scene-project')
check(sync.project[:design][:cabinets].first[:x_mm] == 100 && sync.instance_variable_get(:@dirty),'Pull did not preserve an unpushed native cabinet move')
check(UI.last_message.first.include?('cabinet moves') && sync.instance_variable_get(:@requests).empty?,'Pull did not confirm before replacing a native move')
cancelled=[]
sync.pull('scene-project',on_error:proc { |*error| cancelled << error })
check(cancelled.length==1 && cancelled.first[0]=='Pull cancelled' && cancelled.first[2][:cancelled],'Pull cancellation did not complete its caller')
push_project={schema_version:1,id:'scene-project',revision:1,name:'Native move coherence',room:{walls:[{id:'wall',width_mm:6000,height_mm:2600,thickness_mm:150,origin_mm:[0,0,0],rotation_deg:0,openings:[]}]},design:{style:'modern_gola',settings:{},accessories:{worktops:true,end_scribe_mm:0},cabinets:[{id:'cabinet',local_id:'B01',wall_id:'wall',type:'base_single',width_mm:600,height_mm:720,depth_mm:560,x_mm:0,y_mm:0,z_mm:0,rotation_deg:0,options:{}}]}}
AJBoardKitchen.instance_variable_set(:@job,AJBoardKitchen::ProjectBridge.generate(push_project)[:job])
# Reproduce a cancelled Pull that already captured x=100 in the stored intent,
# while its currently generated job/scene accessories still describe x=0.
push_project[:design][:cabinets].first[:x_mm]=100
sync.instance_variable_set(:@project,push_project)
Sketchup.active_model.define_singleton_method(:active_path) { nil }
sync.define_singleton_method(:apply_project) do |data,dirty:false,preserve_camera:false|
  raise 'Native-move materialization did not preserve the camera request' unless preserve_camera
  @test_rebuild_count=(@test_rebuild_count || 0)+1
  @project=AJBoardKitchen::ProjectBridge.copy(data); @dirty=dirty
  built=AJBoardKitchen::ProjectBridge.generate(@project)[:job]
  AJBoardKitchen.instance_variable_set(:@job,built)
  @root.set_attribute(AJBoardKitchen::DICT,'job',JSON.generate(built))
  @root.set_attribute(AJBoardScaffold::DICT,'job',JSON.generate(built))
  AJBoardKitchen.instance_variable_get(:@view)
end
save_success=[]; save_errors=[]
sync.push(on_success:proc { |saved| save_success << saved[:revision] },on_error:proc { |*error| save_errors << error })
http=sync.instance_variable_get(:@requests).values.first
sent=JSON.parse(http.body,symbolize_names:true)
stored=JSON.parse(scene_root.get_attribute(AJBoardKitchen::DICT,'job'),symbolize_names:true)
check(sync.instance_variable_get(:@test_rebuild_count)==1,'Push did not materialize a captured native move')
check(sent[:generated][:job][:cabinets].first[:pose][0]==100 && stored[:cabinets].first[:pose][0]==100,'Saved model job pose differs from pushed native pose')
stored_top=stored[:cabinets].find { |cab| cab[:accessory] }[:parts].find { |part| part[:material]=='Worktop' }
check(stored_top[:o][0]==100,'Local worktop source was not regenerated with the native move')
cabinet.transformation.origin.x=150.0/25.4
saved=AJBoardKitchen::ProjectBridge.copy(sent[:project]); saved[:revision]=2; saved[:manufacturing]=sent[:generated]
http.finish(200,saved)
check((cabinet.transformation.origin.x*25.4-150).abs<0.001 && sync.instance_variable_get(:@test_rebuild_count)==1,'Async save completion replaced newer native geometry')
check(sync.project[:design][:cabinets].first[:x_mm]==150 && sync.instance_variable_get(:@dirty) && sync.project[:revision]==2,'Async save did not retain newer native moves as unsent edits')
check(save_success==[2] && save_errors.empty?,'Push success did not complete its caller')
sync.instance_variable_set(:@dirty,false)
pull_errors=[]; pull_success=[]
sync.pull('older-project',on_success:proc { |value| pull_success << value[:id] },on_error:proc { |*error| pull_errors << error })
older_request=sync.instance_variable_get(:@requests).values.first
sync.pull('newer-project',on_success:proc { |value| pull_success << value[:id] },on_error:proc { |*error| pull_errors << error })
newer_request=(sync.instance_variable_get(:@requests).values-[older_request]).first
newer=AJBoardKitchen::ProjectBridge.copy(sync.project); newer[:id]='newer-project'
newer_request.finish(200,newer)
older=AJBoardKitchen::ProjectBridge.copy(newer); older[:id]='older-project'
older_request.finish(200,older)
check(sync.project[:id]=='newer-project' && pull_success==['newer-project'] && pull_errors.length==1,'Out-of-order pull replaced the newer project')
check(generated[:job][:input_manifest][:design] == AJBoardKitchen::ProjectBridge.copy(JSON.parse(original))[:design],'Generated input manifest lost source design')
module AJBoardKitchen
  def self.install_toolbar; @test_toolbar_installed=true; end
  def self.build!(*); raise 'Boot inserted a demo into the active model'; end
end
module AJBoardKitchen::Sync
  def self.install; @test_toolbar_installed=true; end
  def self.rehydrate; false; end
end
AJBoardKitchen.boot
check(AJBoardKitchen.instance_variable_get(:@test_toolbar_installed) && sync.instance_variable_get(:@test_toolbar_installed),'Boot did not install toolbars')
puts JSON.pretty_generate(passed: true, cabinet_families: families, checks: ['Legacy manufacturing rules preserved', '2 mm side-specific bands', 'Grooved backs and stretchers', 'World wall transforms', 'Stable UUIDs and numbers after reordering', 'Semantic hob role without B05 artifact', 'Opt-in 10ft worktop/cutouts and 24mm scribes retained','Scribe wall-boundary validation','Unsupported families refused','Async HTTP retention and 409 local-edit preservation','Loopback URL and opaque asset boundaries','Native moves captured; mirrored/tilted roots and geometry edits rejected','Native-move Push regenerates local job/accessories before sending','Async save preserves newer native moves','Generated input manifest preserves design','POST/DELETE and transport/parse/model failure callbacks','Texture and cancellation callbacks complete once','Stale conflicts and out-of-order pulls preserve the current project'])
