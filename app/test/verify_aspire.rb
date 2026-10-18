require_relative '../export'
def check(ok,message);raise message unless ok;end
def records(path)
  lines=File.binread(path).split(/\r?\n/,-1);lines.pop if lines.last==''
  check(lines.size.even?,"Odd DXF stream #{path}")
  result=[];current=[]
  lines.each_slice(2) do |code,value|
    pair=[Integer(code),value]
    if pair[0]==0
      result << current unless current.empty?;current=[]
    end
    current << pair
  end
  result << current unless current.empty?
  result
end
def get(r,code);r.find { |c,_| c==code }&.last;end
def geometry(recs)
  in_entities=false;poly=nil;result=[]
  recs.each do |r|
    type=get(r,0);layer=get(r,8)
    if type=='SECTION';in_entities=get(r,2)=='ENTITIES';next;end
    if type=='ENDSEC';in_entities=false;next;end
    next unless in_entities
    numbers=proc { |*codes| codes.map { |code| Float(get(r,code)).round(6) } }
    case type
    when 'LINE';result << [layer,'LINE',*numbers.call(10,20,11,21)]
    when 'CIRCLE';result << [layer,'CIRCLE',*numbers.call(10,20,40)]
    when 'POLYLINE'
      check(get(r,70)=='1' && get(r,66)=='1','Open or invalid contour')
      poly={layer:layer,points:[]}
    when 'VERTEX'
      check(poly && layer==poly[:layer],'Broken POLYLINE sequence')
      poly[:points]<<numbers.call(10,20)
    when 'SEQEND'
      check(poly && poly[:points].size>=3,'Incomplete contour')
      poly[:points].each_with_index { |a,i| result << [poly[:layer],'LINE',*a,*poly[:points][(i+1)%poly[:points].size]] };poly=nil
    else;raise "Unexpected entity #{type}"
    end
  end
  check(poly.nil?,'Unterminated POLYLINE')
  result.sort
end
root=File.join(AJBoardKitchen::ROOT,'example_export');count=0;labelled=0
%w[parts sheets].each do |kind|
  Dir[File.join(root,'aspire_dxf',kind,'*.dxf')].sort.each do |path|
    r12=records(path);r2k=records(File.join(root,kind=='parts' ? 'parts_dxf' : 'sheets_dxf',File.basename(path)))
    check(r12.flatten(1).include?([1,'AC1009']),'Wrong version')
    check(r12.none? { |r| r.any? { |code,_| [100,330,390].include?(code) } },'Modern subclass/owner in R12')
    layers=r12.select { |r| get(r,0)=='LAYER' }.map { |r| get(r,2) }
    check(layers.uniq==layers && layers.all? { |n| n && n.match?(/\A[A-Za-z0-9_]{1,31}\z/) },'Empty/invalid/duplicate layer')
    used=r12.filter_map { |r| get(r,8) }.uniq
    check((used-layers).empty?,'Undefined layer')
    check(geometry(r12)==geometry(r2k),"Changed geometry: #{path}")
    check(used.any? { |n| n.start_with?('NONCUT_LABEL_PART') },'Missing visible part label')
    used.each do |name|
      next if name.start_with?('NONCUT_')
      check(name.start_with?('CUT_') || name.match?(/\AREVIEW_(A|B|EDGE)_(DRILL|POCKET|GROOVE)_/),"Unclassified layer #{name}")
    end
    count+=1;labelled+=1
  end
end
check(count==436,'Missing Aspire setups')
job=AJBoardKitchen.make_job
type_counts=Hash.new(0);layer_types=Hash.new { |h,k| h[k]=[] }
AJBoardKitchen.parts(job).each do |p|
  p[:operations].each do |o|
    type=AJBoardKitchen::Export.process_type(o);layer=AJBoardKitchen::Export.op_layer(o)
    type_counts[type]+=1;layer_types[layer]<<type
  end
end
check(layer_types.values.all? { |a| a.uniq.size==1 },'Two process types share a layer')
check(AJBoardKitchen::Export.process_type(recipe:'review-cup35',kind:'drill')=='POCKET','Hinge cup not on pocket layer')
check(AJBoardKitchen::Export.process_type(recipe:'review-minifix-cam',kind:'drill')=='POCKET','Minifix recess not on pocket layer')
check(AJBoardKitchen::Export.process_type(recipe:'review-rafix20-housing',kind:'drill')=='POCKET','Rafix recess not on pocket layer')
check(AJBoardKitchen::Export.process_type(recipe:'review-screw-recess',kind:'drill')=='POCKET','Screw recess not on pocket layer')
result={passed:true,version:AJBoardKitchen::VERSION,aspire_files:count,labelled_files:labelled,geometry:'All R12 contours, circles, bands and labels match the R2000 export exactly',processes:type_counts,layer_processes_unique:true,native_aspire_import:'not_verified'}
File.write(File.join(__dir__,'aspire_results.json'),JSON.pretty_generate(result));puts JSON.pretty_generate(result)
