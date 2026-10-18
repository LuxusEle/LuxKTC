# frozen_string_literal: true
# Review lettering uses simple line strokes so SketchUp's CAD importer can see it.
# CAD exports keep real TEXT. Annotation geometry never belongs to cutting layers.
module AJBoardKitchen
  module Annotations
    extend self
    remove_const(:GLYPHS) if const_defined?(:GLYPHS, false)
    # Coordinates: 0..4 across, 0..6 high; spaces separate independent strokes.
    GLYPHS = {
      'A'=>'0,0 0,4 2,6 4,4 4,0;0,3 4,3',
      'B'=>'0,0 0,6 3,6 4,5 4,4 3,3 0,3;3,3 4,2 4,1 3,0 0,0',
      'C'=>'4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1',
      'D'=>'0,0 0,6 2,6 4,4 4,2 2,0 0,0',
      'E'=>'4,6 0,6 0,0 4,0;0,3 3,3',
      'F'=>'0,0 0,6 4,6;0,3 3,3',
      'G'=>'4,5 3,6 1,6 0,5 0,1 1,0 4,0 4,3 2,3',
      'H'=>'0,0 0,6;4,0 4,6;0,3 4,3',
      'I'=>'0,6 4,6;2,6 2,0;0,0 4,0',
      'J'=>'0,1 1,0 3,0 4,1 4,6;2,6 4,6',
      'K'=>'0,0 0,6;4,6 0,2;1,3 4,0',
      'L'=>'0,6 0,0 4,0',
      'M'=>'0,0 0,6 2,3 4,6 4,0',
      'N'=>'0,0 0,6 4,0 4,6',
      'O'=>'1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0',
      'P'=>'0,0 0,6 3,6 4,5 4,4 3,3 0,3',
      'Q'=>'1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0;2,2 4,0',
      'R'=>'0,0 0,6 3,6 4,5 4,4 3,3 0,3;2,3 4,0',
      'S'=>'4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1',
      'T'=>'0,6 4,6;2,6 2,0',
      'U'=>'0,6 0,1 1,0 3,0 4,1 4,6',
      'V'=>'0,6 0,3 2,0 4,3 4,6',
      'W'=>'0,6 0,0 2,3 4,0 4,6',
      'X'=>'0,6 4,0;0,0 4,6',
      'Y'=>'0,6 2,3 4,6;2,3 2,0',
      'Z'=>'0,6 4,6 0,0 4,0',
      '0'=>'1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0;0,1 4,5',
      '1'=>'1,5 2,6 2,0;0,0 4,0',
      '2'=>'0,5 1,6 3,6 4,5 4,4 0,0 4,0',
      '3'=>'0,6 4,6 2,3 4,2 4,1 3,0 0,0',
      '4'=>'3,0 3,6 0,2 4,2',
      '5'=>'4,6 0,6 0,3 3,3 4,2 4,1 3,0 0,0',
      '6'=>'4,6 1,6 0,5 0,1 1,0 3,0 4,1 4,2 3,3 0,3',
      '7'=>'0,6 4,6 1,0',
      '8'=>'1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3 1,3 0,2 0,1 1,0 3,0 4,1 4,2 3,3',
      '9'=>'4,3 1,3 0,4 0,5 1,6 3,6 4,5 4,1 3,0 0,0',
      '-'=>'0,3 4,3', '/'=>'0,0 4,6', '.'=>'2,0 2,0.4',
      ':'=>'2,1 2,1.4;2,4 2,4.4', ';'=>'1,0 2,1 2,2;2,4 2,4.4',
      '='=>'0,2 4,2;0,4 4,4', '+'=>'0,3 4,3;2,1 2,5',
      '('=>'3,6 1,4 1,2 3,0', ')'=>'1,6 3,4 3,2 1,0',
      '['=>'3,6 1,6 1,0 3,0', ']'=>'1,6 3,6 3,0 1,0',
      '|' =>'2,0 2,6', '_' =>'0,0 4,0',
      '?' =>'0,5 1,6 3,6 4,5 4,4 2,2;2,0 2,0.4',
      ' '=>''
    }.freeze

    def number(v); v.to_f.round(2).to_s.sub(/\.0\z/,''); end
    def stroke_lines(text,x,y,height)
      result=[]
      text.to_s.upcase.each_char.with_index do |char,index|
        GLYPHS.fetch(char,GLYPHS.fetch('?')).split(';').each do |stroke|
          points=stroke.split.map { |pair| a,b=pair.split(',').map(&:to_f);[x+(index*5.2+a)*height/6,y+b*height/6] }
          points.each_cons(2) { |a,b| result << [a,b] }
        end
      end
      result
    end
    def operation_name(o)
      case o[:recipe].to_s
      when /cup35/ then 'HINGE CUP'
      when /hinge-plate/ then 'HINGE PLATE'
      when /hinge-fixing/ then 'HINGE FIXING'
      when /rear-hook/ then 'DRAWER REAR HOOK'
      when /locking-plate/ then 'DRAWER LOCK'
      when /undermount-cabinet/ then 'RUNNER FIXING'
      when /minifix-cam/ then 'MINIFIX CAM'
      when /minifix-bolt/ then 'MINIFIX BOLT'
      when /minifix-edge/ then 'MINIFIX EDGE'
      when /ovvo-od830/ then 'OVVO OD830'
      when /rafix20-housing/ then 'RAFIX 20 HOUSING'
      when /rafix20-bolt/ then 'RAFIX BOLT'
      when /dowel/ then 'ASSEMBLY DOWEL'
      when /screw-clearance/ then 'SCREW CLEARANCE'
      when /screw-recess/ then 'SCREW RECESS'
      when /screw-pilot/ then 'SCREW PILOT'
      when /drawer-front/ then 'DRAWER FACE FIXING'
      when /upper-cover-clearance/ then 'COVER SCREW CLEARANCE'
      when /upper-cover-pilot/ then 'COVER SCREW PILOT'
      when /back-groove/ then 'BACK GROOVE'
      else 'DRILL'
      end
    end
    def rows(p,face:nil,machining:true,detail:'compact')
      if detail=='compact'
        bands=%w[L R B T].filter_map do |s|
          t=(p[:edges]||{}).fetch(s,0)
          "#{s}#{number(t)}" if t>0
        end
        return [["#{p[:number]} / #{p[:cabinet_id]}#{face ? " / #{face}" : ''}",'PART_ID'],
          [p[:name].upcase,'PART_NAME'],
          ["#{number(p[:w])} X #{number(p[:h])} X #{number(p[:t])} MM",'PART_SIZE'],
          ["EB #{bands.empty? ? 'NONE' : bands.join(' ')}",'EDGEBAND_LABEL']]
      end
      band=%w[L R B T].map { |s| "#{s}:#{number((p[:edges]||{}).fetch(s,0))}" }.join(' ')
      result=[["#{p[:number]} / #{p[:cabinet_id]}",'PART_ID'],[p[:name].upcase,'PART_NAME'],
        ["CUT #{number(p[:w])} X #{number(p[:h])} X #{number(p[:t])} MM",'PART_SIZE'],
        ["#{face ? "FACE #{face}" : 'A/B OVERVIEW'} / EB #{band} MM (LOCAL A)",'EDGEBAND_LABEL']]
      if machining
        ops=p[:operations].select { |o| !face || o[:face]==face }
        ops.group_by { |o| [o[:face],o[:recipe],o[:diameter],o[:depth],o[:kind],o[:w],o[:h]] }.each_value do |group|
          o=group.first
          size=o[:kind]=='groove' ? "W#{number([o[:w],o[:h]].min)}" : "D#{number(o[:diameter])}"
          result << ["#{o[:face]}: #{group.length}X #{operation_name(o)} #{size} Z#{number(o[:depth])}",'MACHINING_LABEL']
        end
      end
      result
    end
    def wrap(text,limit)
      text.scan(/\S+/).each_with_object([]) do |word,lines|
        if !lines.empty? && lines[-1].length+1+word.length<=limit
          lines[-1] << ' ' << word
        else
          lines.concat(word.scan(/.{1,#{limit}}/))
        end
      end
    end
    # Coordinates remain in sheet/world XY, even for a rotated or B-mirrored part.
    def layout(p,transform,face:nil,machining:true,detail:'compact')
      corners=S.rectangle(p[:w],p[:h]).map { |x,y| transform.call(x,y) }
      x0,x1=corners.map(&:first).minmax;y0,y1=corners.map(&:last).minmax
      w=x1-x0;h=y1-y0;pad=[12.0,w*0.08,h*0.08].min
      size=[detail=='compact' ? 8.0 : 12.0,(w-2*pad)/12.0].min
      raw=rows(p,face:face,machining:machining,detail:detail)
      loop do
        limit=[((w-2*pad)/(size*0.9)).floor,1].max
        lines=raw.flat_map { |text,kind| wrap(text,limit).map { |s| [s,kind] } }
        total=(lines.length-1)*size*1.55+size
        if total<=h-2*pad
          # Prefer a free area of the panel; avoid placing the block in a cutout.
          holes=p[:holes].map { |poly| poly.map { |x,y| transform.call(x,y) } }
          width=lines.map { |s,_| s.length*size*0.9 }.max
          candidates=[[(x0+x1-width)/2,(y0+y1-total)/2],[x0+pad,y0+pad],[x0+pad,y1-pad-total],[x1-pad-width,y0+pad],[x1-pad-width,y1-pad-total]]
          pos=candidates.find do |x,y|
            holes.none? do |poly|
              hx=poly.map(&:first).minmax;hy=poly.map(&:last).minmax
              x<hx[1] && x+width>hx[0] && y<hy[1] && y+total>hy[0]
            end
          end
          unless pos
            size*=0.8;next if size>0.25
            pos=candidates.first
          end
          x,y=pos
          return lines.each_with_index.map { |(text,kind),i| {text:text,kind:kind,x:x,y:y+total-size-i*size*1.55,size:size,width:w-2*pad} }
        end
        size*=0.85
      end
    end
  end
end
