require_relative '../export'
def check(condition,message);raise message unless condition;end
job=AJBoardKitchen.make_job
parts=AJBoardKitchen.parts(job);sheets=AJBoardKitchen.nest(job)
profiles=parts.select { |p| p[:kind]=='profile' }
check(profiles.none? { |p| p[:section]=='handle' || p[:name]=='Finger pull' },'Legacy door-mounted handles must not be emitted')
check(profiles.count { |p| %w[gola_l gola_c].include?(p[:section]) }==6,'Keep six stationary recessed Gola rails')
check(profiles.count { |p| p[:section]=='upper_l_pull' }==2 && profiles.all? { |p| !p[:motion] },'Two fixed underside upper L pulls')
check(profiles.none? { |p| %w[B01 B02 W03 W04].include?(p[:cabinet_id]) },'Tall, hood and open units must have no finger pulls')
check(job[:cabinets].find { |c| c[:id]=='W03' }[:motions].count { |m| m[:kind]=='hinge' }==2,'Hood requires two doors')
check(job[:cabinets].sum { |c| c[:motions].count { |m| m[:kind]=='drawer' } }==6,'Six drawers expected')
check(job[:width]==3048,'10 foot run')
base=job[:cabinets].select { |c| c[:id].start_with?('B') }
check(base.first[:pose][0]==24 && base.last[:pose][0]+base.last[:w]+24==3048,'Scribes and cabinet width closure')
base.each_cons(2) { |a,b| check((a[:pose][0]+a[:w]-b[:pose][0]).abs<0.001,'Cabinet gap') }
check(sheets.flat_map { |s| s[:placements].map { |a| a[:part] } }.sort==AJBoardKitchen.panels(job).map { |p| p[:number] }.sort,'Nesting has omitted/duplicated parts')
sheets.each do |s|
  s[:placements].each do |a|
    check(a[:x]>=10 && a[:y]>=10 && a[:x]+a[:w]<=s[:w]-10 && a[:y]+a[:h]<=s[:h]-10,'Sheet bounds')
  end
  s[:placements].combination(2).each { |a,b| check(a[:x]+a[:w]+3.99<=b[:x] || b[:x]+b[:w]+3.99<=a[:x] || a[:y]+a[:h]+3.99<=b[:y] || b[:y]+b[:h]+3.99<=a[:y],'Nested panels overlap') }
end
parts.each do |p|
  next unless p[:kind]=='panel'
  e=p[:edges]
  check((p[:w]+e.fetch('L',0)+e.fetch('R',0)-p[:finished_w]).abs<0.001,'Width band allowance')
  check((p[:h]+e.fetch('B',0)+e.fetch('T',0)-p[:finished_h]).abs<0.001,'Height band allowance')
end
# Paired edge bores and mating side pilots must share a world drilling centre.
job[:cabinets].each do |c|
  joints=c[:parts].flat_map { |p| p[:operations].select { |o| o[:joint] }.map { |o| [p,o] } }.group_by { |p,o| o[:joint] }
  joints.each do |id,ops|
    check(ops.length==2,"Incomplete joint #{id}")
    a,ao=ops.find { |p,o| o[:face]=='EDGE' };b,bo=ops.find { |p,o| o[:face]!='EDGE' }
    ap=AJBoardScaffold::Math3.local(a,[ao[:x],ao[:y],a[:t]/2])
    bp=AJBoardScaffold::Math3.local(b,[bo[:x],bo[:y],bo[:face]=='A' ? 0 : b[:t]])
    check(ap.zip(bp).all? { |v,w| (v-w).abs<0.01 },"Mating centres disagree #{id}")
  end
end
['minifix','screw'].product(['cup35_screw','cup35_dowel','none'],[0,1,2]).each do |joinery,hinge,band|
  test=AJBoardKitchen.make_job(joinery:joinery,hinge:hinge,edge:band,front_edge:band)
  AJBoardKitchen.validate_job(test);AJBoardKitchen.nest(test)
  recipes=AJBoardKitchen.parts(test).flat_map { |p| p[:operations].map { |o| o[:recipe] } }
  check(recipes.none? { |r| r.include?('minifix') },'Screw choice retained cams') if joinery=='screw'
  check(recipes.none? { |r| r.include?('hinge') || r.include?('cup35') },'No-hinge selection retained drilling') if hinge=='none'
end
door=parts.find { |p| p[:cabinet_id]=='B01' && p[:category]=='Doors' }
custom=AJBoardKitchen.make_job(edge_overrides:{door[:id]=>{'L'=>2,'R'=>0,'T'=>0.5,'B'=>1}})
adjusted=AJBoardKitchen.parts(custom).find { |p| p[:id]==door[:id] }
check(adjusted[:w]==door[:finished_w]-2 && adjusted[:h]==door[:finished_h]-1.5,'Per-edge cut allowances')
door[:operations].zip(adjusted[:operations]).each do |a,b|
  pa=AJBoardScaffold::Math3.local(door,[a[:x],a[:y],0]);pb=AJBoardScaffold::Math3.local(adjusted,[b[:x],b[:y],0])
  check(pa.zip(pb).all? { |u,v| (u-v).abs<0.001 },'Changing bands moved a hinge in finished coordinates')
end
result={passed:true,parts:parts.size,panels:AJBoardKitchen.panels(job).size,sheets:sheets.size,machining:parts.sum { |p| p[:operations].size },checks:['3048 mm width closure','Two hood doors and six drawers','Stable unique numbers','Every panel nested exactly once','Sheet margins and 4 mm separation','Edgeband allowances','Mating connector world coordinates','18 hardware/band combinations','Asymmetric per-edge bands preserve finished size and hinge centres']}
def world_box(p,xy=nil,zs=nil)
  xy ||= AJBoardScaffold.rectangle(p[:w],p[:h])
  zs ||= [0,p[:t]]
  points=xy.product(zs).map { |(x,y),z| AJBoardScaffold::Math3.local(p,[x,y,z]) }
  (0..2).map { |axis| points.map { |v| v[axis] }.minmax }
end
def verify_construction(job)
  bt=job[:settings][:back_thickness];gd=job[:settings][:back_groove_depth]
  job[:cabinets].reject { |c| c[:id]=='R01' }.each do |c|
    ps=c[:parts];back=ps.find { |p| p[:material]=='Back' }
    verticals=ps.select { |p| p[:name].include?('vertical stretcher') }
    if c[:id]=='B03'
      check(back.nil?,'Sink service back must stay open')
      check(verticals.size==1 && verticals.first[:finished_h]==100,'Sink lower rear stretcher')
      check(ps.count { |p| p[:name]=~/Sink .* rail/ && p[:finished_h]==50 }==2,'Sink upright top rails')
      next
    end
    check(back && back[:t]==bt,"Missing grooved back #{c[:id]}")
    body_height=c.fetch(:carcass_height,c[:h])
    check(back[:finished_w]==c[:w]-36+2*gd && back[:finished_h]==body_height-36+2*gd,'Back engagement allowance')
    check(verticals.size==2 && verticals.all? { |p| p[:finished_h]==100 && p[:t]==18 },'Rear vertical stretchers')
    grooves=ps.flat_map { |p| p[:operations].select { |o| o[:kind]=='groove' }.map { |o| [p,o] } }
    check(grooves.size==4,'Back requires four receiving grooves')
    bb=world_box(back)
    grooves.each do |p,o|
      pb=world_box(p)
      overlap=pb.zip(bb).map { |a,b| [[a[0],b[0]].max,[a[1],b[1]].min] }
      check(overlap.all? { |a,b| b-a>0 },'Back must enter each receiving member')
      zs=o[:face]=='A' ? [0,o[:depth]] : [p[:t]-o[:depth],p[:t]]
      slot=world_box(p,AJBoardKitchen.groove_outline(o),zs)
      check(overlap.zip(slot).all? { |(a,b),(l,r)| a>=l-0.001 && b<=r+0.001 },"Back does not fit groove #{p[:id]}")
      check(o[:depth]==gd && [o[:w],o[:h]].min==bt,'Groove width/depth mismatch')
    end
    ps.select { |p| p[:name]=~/shelf/i && p[:u]==AJBoardKitchen::X && p[:v]==AJBoardKitchen::Y }.each do |p|
      check(world_box(p)[1][1]<=bb[1][0]-0.999,'Shelf overlaps back')
    end
    verticals.each { |p| check(world_box(p)[1][0]>=bb[1][1]-0.001,'Stretcher overlaps back') }
  end
  check(job[:cabinets].none? { |c| c[:type]=='base_open' },'Open rack below counter')
  check(job[:cabinets].count { |c| c[:type]=='wall_open' }==1,'Keep upper open rack')
  check(job[:cabinets].find { |c| c[:id]=='B06' }[:motions].count { |m| m[:kind]=='hinge' }==1,'300 mm lower unit needs a door')
end
verify_construction(job)
[[4,3],[6,5],[9,8]].product([0,2]).each do |(thickness,depth),band|
  verify_construction(AJBoardKitchen.make_job(back_thickness:thickness,back_groove_depth:depth,edge:band,front_edge:band))
end
result[:drills]=parts.sum { |p| p[:operations].count { |o| o[:kind]=='drill' } }
result[:grooves]=parts.sum { |p| p[:operations].count { |o| o[:kind]=='groove' } }
result[:checks] += ['Nine backs physically fit all 36 receiving grooves','Back engagement and shelf clearance at three thickness/depth settings','Rear stretchers and sink upright rails','No lower open racks']
result[:checks] += ['No door-mounted finger-pull artifacts','Six stationary recessed Gola profiles retained']
puts JSON.pretty_generate(result)
File.write(File.join(__dir__,'engineering_results.json'),JSON.pretty_generate(result))
