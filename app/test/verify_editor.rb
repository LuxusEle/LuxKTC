require_relative '../export'
def check(c,m);raise m unless c;end
def rejected(message)
  begin;yield;rescue RuntimeError,ArgumentError;return;end
  raise "Accepted invalid change: #{message}"
end
def verify_nesting(job)
  sheets=AJBoardKitchen.nest(job)
  check(sheets.flat_map { |s| s[:placements].map { |p| p[:part] } }.sort==AJBoardKitchen.panels(job).map { |p| p[:number] }.sort,'Nesting coverage')
  sheets.each do |s|
    s[:placements].combination(2).each do |a,b|
      gap=job[:settings][:kerf]-0.001
      check(a[:x]+a[:w]+gap<=b[:x] || b[:x]+b[:w]+gap<=a[:x] || a[:y]+a[:h]+gap<=b[:y] || b[:y]+b[:h]+gap<=a[:y],'Nested overlap')
    end
  end
end
module K;extend self;def cab(j,id);j[:cabinets].find { |c| c[:id]==id };end;end
base=AJBoardKitchen.make_job;original=Marshal.dump(base[:settings]);tested=[]
%w[left right both extend].each do |direction|
  c=AJBoardKitchen::Layout.edit(base[:settings],'B04',{w:500},fill:direction)
  job=AJBoardKitchen.make_job(c);verify_nesting(job)
  check(K.cab(job,'B04')[:w]==500,'Selected width ignored')
  check(job[:width]==(direction=='extend' ? 3098 : 3048),'Run closure')
  %w[B02 B03 B05].each { |id| check(K.cab(job,id)[:w]==K.cab(base,id)[:w],"Locked width #{id}") }
  AJBoardKitchen::Layout::UPPER.each do |id,_,anchor|
    check(K.cab(job,id)[:w]==K.cab(job,anchor)[:w] && K.cab(job,id)[:pose][0]==K.cab(job,anchor)[:pose][0],'Upper alignment')
  end
  check(AJBoardKitchen.parts(job).map { |p| [p[:id],p[:number]] }==AJBoardKitchen.parts(base).map { |p| [p[:id],p[:number]] },'Changing width renumbered parts')
  worktop=K.cab(job,'R01')[:parts].first
  worktop[:holes].zip(%w[B03 B05]).each do |loop,id|
    cx=loop.map(&:first).sum/loop.size+worktop[:o][0]
    check((cx-K.cab(job,id)[:pose][0]-K.cab(job,id)[:w]/2).abs<0.001,'Cutout no longer centered over its cabinet')
  end
  tested<<"resize #{direction}"
end
check(Marshal.dump(base[:settings])==original,'Edit mutated its original settings')
rejected('fixed oven width') { AJBoardKitchen::Layout.edit(base[:settings],'B02',{w:550}) }
rejected('insufficient unlocked width') { AJBoardKitchen::Layout.edit(base[:settings],'B04',{w:850},fill:'right') }
rejected('invalid numeric') { AJBoardKitchen::Layout.edit(base[:settings],'B04',{w:Float::NAN}) }
c=AJBoardKitchen::Layout.edit(base[:settings],'W02',{w:500,h:650,d:350,joinery:'screw'},fill:'right')
job=AJBoardKitchen.make_job(c)
check(K.cab(job,'B04')[:w]==500 && K.cab(job,'W02')[:h]==650 && K.cab(job,'B04')[:h]==720,'Upper independent height / linked width')
check(K.cab(job,'W02')[:options][:config][:joinery]=='screw' && K.cab(job,'B04')[:options][:config][:joinery]=='minifix','Per-cabinet recipe isolation')
c=AJBoardKitchen::Layout.edit(base[:settings],'B04',{h:760,d:600,edge:2,front_edge:2},fill:'both');job=AJBoardKitchen.make_job(c);verify_nesting(job)
check(%w[B03 B04 B05 B06].all? { |id| K.cab(job,id)[:h]==760 },'Shared worktop height')
top=K.cab(job,'R01')[:parts].first;check(top[:o][2]==860 && top[:h]==660,'Worktop dimensions not regenerated')
c=AJBoardKitchen::Layout.edit(c,'B04',{joinery:'inherit',edge:'inherit',front_edge:'inherit'},fill:'both')
check(!c[:cabinet_overrides]['B04'].key?(:edge),'Restore inherited settings')
count=0
export_root=File.join(AJBoardKitchen::ROOT,'test_output','connector_checks')
%w[minifix screw minifix_dowel dowel ovvo_od830 rafix].product([0,1,2]).each do |recipe,band|
  job=AJBoardKitchen.make_job(joinery:recipe,edge:band,front_edge:band);verify_nesting(job)
  all=AJBoardKitchen.parts(job)
  check(all.map { |p| [p[:id],p[:number]] }==AJBoardKitchen.parts(base).map { |p| [p[:id],p[:number]] },'Connector changes renumbered parts')
  job[:cabinets].each do |cab|
    joints=cab[:parts].flat_map { |p| p[:operations].select { |o| o[:joint] }.map { |o| [p,o] } }.group_by { |p,o| o[:joint] }
    joints.each do |id,pairs|
      check(pairs.size==2,"Incomplete joint #{id}")
      points=pairs.map do |p,o|
        pos=o[:contact]||[o[:x],o[:y],o[:face]=='EDGE' ? p[:t]/2 : o[:face]=='A' ? 0 : p[:t]]
        # Through screws are drilled from the OUTSIDE side face; entry lies one
        # panel thickness from the mating edge, along the screw axis.
        AJBoardScaffold::Math3.local(p,pos)
      end
      distance=points[0].zip(points[1]).map { |a,b| (a-b).abs }
      expected=recipe=='screw' ? 18 : 0
      check((distance[0]-expected).abs<0.001 && distance.drop(1).all? { |d| d<0.001 },"Mating centres #{recipe} #{id}: #{distance}")
      count+=1
    end
  end
  ops=all.flat_map { |p| p[:operations] }
  check(ops.none? { |o| o[:recipe].include?('minifix') },'Old cams retained') unless recipe.start_with?('minifix')
  if recipe=='ovvo_od830'
    own=ops.select { |o| o[:recipe].include?('ovvo') }
    check(own.all? { |o| o[:diameter]==8 && o[:depth]==(o[:face]=='EDGE' ? 18 : 13) },'OVVO OD830 drilling sizes')
  end
  if band==1
    folder=File.join(export_root,recipe);chosen=all.select { |p| p[:cabinet_id]=='B04' && ['Side left','Left side','Bottom','Rear bottom vertical stretcher'].include?(p[:name]) }
    # Include a mating side regardless of the inherited scaffold's label.
    chosen << K.cab(job,'B04')[:parts].find { |p| p[:u]==AJBoardKitchen::Y && p[:v]==AJBoardKitchen::Z }
    chosen=chosen.compact.uniq
    AJBoardKitchen::Export.part_dxfs(folder,chosen)
    File.write(File.join(folder,'parts.json'),JSON.pretty_generate(chosen))
  end
  tested<<"#{recipe}, band #{band}"
end
result={passed:true,version:AJBoardKitchen::VERSION,mating_pairs_checked:count,cases:tested,checks:['Atomic edit settings','Bounded redistribution and locked widths','Fixed appliance rejection','Independent upper height with linked width','Shared worktop height/depth/cutout recalculation','Stable part IDs and numbers','Every panel re-nested without overlap','Six connector types at three band thicknesses','Rafix off-centre bolt axes','OVVO OD830 distinct face and edge depths']}
File.write(File.join(__dir__,'editor_results.json'),JSON.pretty_generate(result));puts JSON.pretty_generate(result)
