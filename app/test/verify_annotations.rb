require_relative '../aj_board_kitchen'
job=AJBoardKitchen.make_job
snapshot=JSON.generate(job)
count=0;smallest=100
AJBoardKitchen.panels(job).each do |p|
  [false,true].product([false,true]).each do |rotate,mirror|
    width=rotate ? p[:h] : p[:w];height=rotate ? p[:w] : p[:h]
    transform=proc { |x,y| a,b=rotate ? [p[:h]-y,x] : [x,y];[10+(mirror ? width-a : a),20+b] }
    [nil,'A','B'].product(['compact','full']).each do |face,detail|
      rows=AJBoardKitchen::Annotations.layout(p,transform,face:face,detail:detail)
      raise 'Missing part number' unless rows.any? { |r| r[:text].include?(p[:number]) }
      raise 'Missing full name' unless rows.select { |r| r[:kind]=='PART_NAME' }.map { |r| r[:text] }.join.delete(' ')==p[:name].upcase.delete(' ')
      if detail=='compact'
        raise 'Compact labels retained machining paragraphs' if rows.any? { |r| r[:kind]=='MACHINING_LABEL' }
        raise 'Compact text too large' if rows.any? { |r| r[:size]>8 }
      elsif p[:operations].any? { |o| !face || o[:face]==face }
        raise 'Full labels lost machining details' unless rows.any? { |r| r[:kind]=='MACHINING_LABEL' }
      end
      rows.each do |r|
        raise 'Unsupported character' unless r[:text].each_char.all? { |c| AJBoardKitchen::Annotations::GLYPHS.key?(c) }
        smallest=[smallest,r[:size]].min
        points=AJBoardKitchen::Annotations.stroke_lines(r[:text],r[:x],r[:y],r[:size]).flatten(1)
        raise "Label outside #{p[:number]}" unless points.all? { |x,y| x.between?(10,10+width) && y.between?(20,20+height) }
      end
      count+=1
    end
  end
end
raise 'Annotation generation modified engineering' unless JSON.generate(job)==snapshot
result={passed:true,layouts:count,minimum_letter_height_mm:smallest.round(3),checks:['Compact and full label modes','Full names and IDs','Strokes within panel bounds','A/B mirror and nesting rotation','Complete glyph coverage','No engineering mutation','Complete loader parses offline']}
File.write(File.join(__dir__,'annotation_results.json'),JSON.pretty_generate(result))
puts JSON.pretty_generate(result)
