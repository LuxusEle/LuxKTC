require_relative '../engineering'
require 'json'

def check(ok,message); raise message unless ok; end
def near(a,b); (a-b).abs<0.001; end
def world(p,point); AJBoardScaffold::Math3.local(p,point); end
def finished_origin(p)
  e=p[:edges]||{}
  world(p,[-e.fetch('L',0),-e.fetch('B',0),0])
end

def verify_uppers(job)
  gap=job[:settings][:upper_finger_gap];recess=job[:settings][:upper_cover_recess]
  job[:cabinets].select { |c| c[:id].start_with?('W') }.each do |c|
    ps=c[:parts];cover=ps.find { |p| p[:upper_cover] };floor=ps.find { |p| p[:name]=='Bottom' }
    front=ps.select { |p| p[:category]=='Doors' }
    pull=ps.select { |p| p[:section]=='upper_l_pull' }
    should_pull=%w[W01 W02].include?(c[:id])
    check(cover && cover[:t]==18,"Missing 18 mm cover #{c[:id]}")
    check(near(c[:carcass_height]+c[:carcass_base_z],600),'Carcass top moved')
    check(near(c[:carcass_base_z],gap+19.5),'Carcass lower reveal')
    check(near(finished_origin(cover)[1],-330+recess),'Cover front recess')
    check(near(cover[:o][2]+18,floor[:o][2]),'Cover must meet carcass bottom')
    front.each do |p|
      check(near(p[:finished_h],597) && near(finished_origin(p)[2],1.5),'Full-height front dimensions')
      check(near(cover[:o][2]-finished_origin(p)[2],gap),'Finger clearance to finished door bottom')
    end
    check(pull.size==(should_pull ? 1 : 0),"Wrong finger-pull placement #{c[:id]}")
    if should_pull
      p=pull.first
      check(!p[:motion] && p[:category]=='Finger pulls','Pull must stay fixed to cabinet')
      points=p[:outline].map { |x,y| world(p,[x,y,0]) }
      check(near(points.map { |q| q[1] }.min,-328),'Pull front clearance behind door')
      check(near(points.map { |q| q[1] }.max,finished_origin(cover)[1]),'L rear leg must meet cover front')
      check(near(p[:t],c[:w]),'Full-width upper pull')
      # Probe the cavity and top flange. An upward-facing L fails these checks.
      check(!AJBoardScaffold::Math3.inside?([p[:w]/2,1],p[:outline]),'L cavity must open down')
      check(AJBoardScaffold::Math3.inside?([p[:w]/2,17.25],p[:outline]),'L needs a top flange')
      check(!cover[:edges].key?('B'),'Covered front edge must not receive automatic band')
    else
      check(cover[:edges].fetch('B',0)==job[:settings][:edge],'Exposed cover front needs band allowance')
    end
    clearance=floor[:operations].select { |o| o[:recipe]=='review-upper-cover-clearance' }
    pilots=cover[:operations].select { |o| o[:recipe]=='review-upper-cover-pilot' }
    check(clearance.size==4 && pilots.size==4,'Four cover fixing positions required')
    clearance.zip(pilots).each do |a,b|
      # Through bottom exit and cover pilot entry are the same world point.
      pa=world(floor,[a[:x],a[:y],0]);pb=world(cover,[b[:x],b[:y],18])
      check(pa.zip(pb).all? { |x,y| near(x,y) },'Cover fixings not coaxial')
      check(a[:face]=='B' && a[:depth]==18 && b[:face]=='B' && b[:depth]==12,'Cover fixing face/depth')
    end
    if c[:id]=='W03'
      check(front.size==2,'Hood paired fronts')
      check(floor[:holes].size==1 && cover[:holes].size==1,'Hood needs an aperture in both boards')
      loops=[floor,cover].map { |p| p[:holes][0].map { |x,y| world(p,[x,y,0]).first(2) } }
      check(loops[0]==loops[1],'Hood apertures must align')
      box=c[:hardware].find { |h| h[:name]=='Extractor envelope' }
      opening=c[:upper_underside][:hood_opening]
      check(box[:o]==[opening[:x],opening[:y],cover[:o][2]],'Hood placement at aperture')
      check(box[:size].first(2)==[opening[:w],opening[:d]],'Hood width/depth at aperture')
      shelf=ps.find { |p| p[:name]=='Hood isolation shelf' }
      check(box[:o][2]+box[:size][2]<shelf[:o][2],'Hood crosses isolation shelf')
      # No drill circle or back groove may fall into the new cassette aperture.
      [floor,cover].each do |p|
        p[:operations].each do |o|
          points=o[:kind]=='groove' ? AJBoardKitchen.groove_outline(o) : 32.times.map { |i| a=i*Math::PI/16;[o[:x]+o[:diameter]/2*Math.cos(a),o[:y]+o[:diameter]/2*Math.sin(a)] }
          check(points.none? { |q| AJBoardScaffold::Math3.inside?(q,p[:holes][0]) },'Machining enters hood aperture')
        end
      end
    end
  end
end

job=AJBoardKitchen.make_job
verify_uppers(job)
variants=0
[20,40].product([25,45],[0,2]).each do |gap,recess,edge|
  verify_uppers(AJBoardKitchen.make_job(upper_finger_gap:gap,upper_cover_recess:recess,edge:edge,front_edge:edge))
  variants+=1
end
ps=AJBoardKitchen.parts(job)
result={passed:true,version:AJBoardKitchen::VERSION,upper_pull_cabinets:ps.select { |p| p[:section]=='upper_l_pull' }.map { |p| p[:cabinet_id] },
  upper_cover_panels:ps.select { |p| p[:upper_cover] }.map { |p| p[:number] },setting_extremes_checked:variants,
  checks:['No finger pull on tall, hood or open units','600 mm overall upper envelope; 597 mm fronts; 555.5 mm default carcasses','18 mm covers; 25 mm default lower clearance; 30 mm default recess','Fixed L top flange and downward-opening cavity','Cover clearance/pilot holes coaxial after edge allowances','Aligned hood apertures clear drilling and rear grooves']}
if ARGV[0]
  before=JSON.parse(File.read(ARGV[0]))
  after=JSON.parse(JSON.generate(job))
  old=before['cabinets'].flat_map { |c| c['parts'] }
  current=after['cabinets'].flat_map { |c| c['parts'] }.to_h { |p| [p['id'],p] }
  old.each do |p|
    next if p['section']=='handle'
    q=current.fetch(p['id'])
    check(p['number']==q['number'] && p['name']==q['name'],'Existing part identity changed')
    check(p==q,"Base/tall/room part changed: #{p['id']}") unless p['cabinet_id'].start_with?('W')
  end
  result[:checks] << 'All original part IDs/numbers retained; base/tall/room geometry and machining unchanged'
end
File.write(File.join(__dir__,'upper_construction_results.json'),JSON.pretty_generate(result))
puts JSON.pretty_generate(result)
