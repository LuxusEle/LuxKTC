# frozen_string_literal: true
require_relative 'engineering' unless defined?(AJBoardKitchen::Board)
require_relative 'annotations' unless defined?(AJBoardKitchen::Annotations)

module AJBoardKitchen
  class DXF
    # Start from a complete, validated R2000 document. The former writer used
    # an R12-like entity stream under an AC1015 header, which strict CAD
    # importers can reject even when a tolerant reader repairs it.
    @template=nil
    def self.template
      @template ||= JSON.parse(File.read(File.join(__dir__,'vendor','dxf_r2000_template.json')),symbolize_names:true)
    end
    def initialize(sketchup_labels:false)
      @entities=[];@layers={};@next_handle=0x100000;@bounds=[];@sketchup_labels=sketchup_labels
    end
    def handle
      result=@next_handle.to_s(16).upcase;@next_handle+=1;result
    end
    def entity(type,layer,pairs)
      @layers[layer] ||= handle unless layer=='0'
      subclass={'LINE'=>'AcDbLine','CIRCLE'=>'AcDbCircle','TEXT'=>'AcDbText'}.fetch(type)
      @entities.concat([[0,type],[5,handle],[330,self.class.template[:modelspace_owner]],
        [100,'AcDbEntity'],[8,layer],[100,subclass],*pairs.each_slice(2).to_a])
      @entities << [100,'AcDbText'] if type=='TEXT'
    end
    def line(a,b,layer='CUT')
      @bounds.concat([a,b]);entity('LINE',layer,[10,a[0],20,a[1],30,0,11,b[0],21,b[1],31,0])
    end
    def poly(points,layer='CUT'); points.each_with_index { |p,i| line(p,points[(i+1)%points.length],layer) }; end
    def circle(x,y,r,layer)
      @bounds.concat([[x-r,y-r],[x+r,y+r]]);entity('CIRCLE',layer,[10,x,20,y,30,0,40,r])
    end
    def text(s,x,y,height=15,layer='PART_ID')
      if @sketchup_labels
        Annotations.stroke_lines(s,x,y,height).each { |a,b| line(a,b,"NONCUT_LABEL_#{layer}") }
        return
      end
      label=s.to_s.gsub(/[\r\n]/,' ').each_char.map { |c| c.ascii_only? ? c : c.encode('UTF-16BE').unpack('n*').map { |u| format('\\U+%04X',u) }.join }.join
      @bounds.concat([[x,y],[x+height*label.length,y+height]])
      entity('TEXT',layer,[10,x,20,y,30,0,40,height,1,label,50,0,7,'Standard'])
    end
    def save(path)
      template=self.class.template;tags=template[:tags].map(&:dup)
      start=tags.each_index.find { |i| tags[i]==[0,'TABLE'] && tags[i+1]==[2,'LAYER'] }
      finish=((start+2)...tags.length).find { |i| tags[i]==[0,'ENDTAB'] }
      count=((start+2)...finish).find { |i| tags[i][0]==70 }
      tags[count][1]=tags[count][1].to_i+@layers.size
      first_layer=tags.index([0,'LAYER'])
      next_record=((first_layer+1)...tags.length).find { |i| tags[i][0]==0 }
      plotstyle=tags[first_layer...next_record].find { |code,_| code==390 }&.last
      raise 'DXF template is missing its Normal plot style' unless plotstyle
      layers=@layers.flat_map do |name,id|
        raise 'Empty DXF layer name' if name.to_s.strip.empty?
        color=name.include?('POCKET') ? 6 : name.include?('DRILL') || name.include?('GROOVE') ? 1 : name.include?('EDGE') ? 3 : 7
        [[0,'LAYER'],[5,id],[330,template[:layer_table_handle]],[100,'AcDbSymbolTableRecord'],
         [100,'AcDbLayerTableRecord'],[2,name],[70,0],[62,color],[6,'Continuous'],[370,-3],[390,plotstyle]]
      end
      tags[finish,0]=layers
      insertion=tags.each_index.find { |i| tags[i]==[0,'SECTION'] && tags[i+1]==[2,'ENTITIES'] }+2
      # Dense stroke lettering can produce hundreds of thousands of tags.
      # Slice assignment avoids splatting them onto Ruby's argument stack.
      tags[insertion,0]=@entities
      seed=tags.index([9,'$HANDSEED']);tags[seed+1]=[5,@next_handle.to_s(16).upcase]
      unless @bounds.empty?
        ['$EXTMIN','$EXTMAX'].each_with_index do |key,i|
          pos=tags.index([9,key]);xy=[0,1].map { |axis| @bounds.map { |p| p[axis] }.minmax[i] }
          tags[pos+1,3]=[[10,xy[0]],[20,xy[1]],[30,0]]
        end
      end
      File.binwrite(path,tags.map { |code,value| format("%3d\r\n%s\r\n",code,value.is_a?(Float) ? value.round(6) : value) }.join)
    end
  end

  # Legacy 2D interchange for Aspire's older importer. R12 has no AcDb
  # subclasses, owner dictionaries or plot-style pointers to misinterpret.
  # Coordinates remain millimetres; set the receiving Aspire job to mm.
  class AspireDXF < DXF
    def entity(type,layer,pairs)
      raise "Invalid R12 layer name: #{layer.inspect}" unless layer.to_s.match?(/\A[A-Za-z0-9_]{1,31}\z/)
      @layers[layer] ||= handle unless layer=='0'
      @entities.concat([[0,type],[5,handle],[8,layer],*pairs.each_slice(2).to_a])
    end
    def poly(points,layer='CUT')
      raise 'A closed contour needs at least three vertices' if points.length<3
      @bounds.concat(points)
      entity('POLYLINE',layer,[66,1,10,0.0,20,0.0,30,0.0,70,1])
      points.each { |x,y| entity('VERTEX',layer,[10,x,20,y,30,0.0,70,0]) }
      entity('SEQEND',layer,[])
    end
    def save(path)
      tags=[[999,'AJ BOARD KITCHEN - R12 2D - ALL COORDINATES IN MILLIMETRES'],
        [0,'SECTION'],[2,'HEADER'],[9,'$ACADVER'],[1,'AC1009'],
        [9,'$LUNITS'],[70,2],[9,'$LUPREC'],[70,3],
        [9,'$INSBASE'],[10,0.0],[20,0.0],[30,0.0]]
      unless @bounds.empty?
        ['$EXTMIN','$EXTMAX'].each_with_index do |key,i|
          xy=[0,1].map { |axis| @bounds.map { |p| p[axis] }.minmax[i] }
          tags.concat([[9,key],[10,xy[0]],[20,xy[1]],[30,0.0]])
        end
      end
      tags.concat([[0,'ENDSEC'],[0,'SECTION'],[2,'TABLES'],
        [0,'TABLE'],[2,'LTYPE'],[70,1],[0,'LTYPE'],[2,'CONTINUOUS'],[70,0],[3,'Solid line'],[72,65],[73,0],[40,0.0],[0,'ENDTAB'],
        [0,'TABLE'],[2,'LAYER'],[70,@layers.size+1]])
      (['0']+@layers.keys).each do |name|
        color=name.include?('POCKET') ? 6 : name.include?('DRILL') || name.include?('GROOVE') ? 1 : name.include?('EDGE') ? 3 : 7
        tags.concat([[0,'LAYER'],[2,name],[70,0],[62,color],[6,'CONTINUOUS']])
      end
      tags.concat([[0,'ENDTAB'],[0,'TABLE'],[2,'STYLE'],[70,1],
        [0,'STYLE'],[2,'Standard'],[70,0],[40,0.0],[41,1.0],[50,0.0],[71,0],[42,2.5],[3,'txt'],[4,''],[0,'ENDTAB'],
        [0,'ENDSEC'],[0,'SECTION'],[2,'BLOCKS'],[0,'ENDSEC'],[0,'SECTION'],[2,'ENTITIES']])
      tags.concat(@entities)
      tags.concat([[0,'ENDSEC'],[0,'EOF']])
      File.binwrite(path,tags.map { |code,value| format("%3d\r\n%s\r\n",code,value.is_a?(Float) ? value.round(6) : value) }.join)
    end
  end

  # Small dependency-free vector PDF writer, so the SketchUp button works offline.
  class PDF
    W=595.28 unless const_defined?(:W)
    H=841.89 unless const_defined?(:H)
    attr_reader :pages
    def initialize; @pages=[]; page; end
    def page; @pages << +''; end
    def add(s); @pages[-1]<<s<<"\n"; end
    def color(r,g,b); add("#{r} #{g} #{b} RG #{r} #{g} #{b} rg"); end
    def text(s,x,y,size=9)
      str=s.to_s.encode('Windows-1252',invalid: :replace,undef: :replace,replace:'?').gsub(/[\\()]/) { |m| '\\'+m }
      add("BT /F1 #{size} Tf 1 0 0 1 #{x.round(3)} #{(H-y).round(3)} Tm (#{str}) Tj ET")
    end
    def line(x1,y1,x2,y2,width=0.5)
      add("#{width} w #{x1.round(3)} #{(H-y1).round(3)} m #{x2.round(3)} #{(H-y2).round(3)} l S")
    end
    def rect(x,y,w,h,fill:false)
      add("#{x.round(3)} #{(H-y-h).round(3)} #{w.round(3)} #{h.round(3)} re #{fill ? 'f' : 'S'}")
    end
    def circle(x,y,r)
      c=r*0.55228475; yy=H-y
      add("#{x+r} #{yy} m #{x+r} #{yy+c} #{x+c} #{yy+r} #{x} #{yy+r} c #{x-c} #{yy+r} #{x-r} #{yy+c} #{x-r} #{yy} c #{x-r} #{yy-c} #{x-c} #{yy-r} #{x} #{yy-r} c #{x+c} #{yy-r} #{x+r} #{yy-c} #{x+r} #{yy} c S")
    end
    def save(path)
      objects=[]; objects<<'<< /Type /Catalog /Pages 2 0 R >>'
      objects<<"<< /Type /Pages /Count #{@pages.size} /Kids [#{@pages.each_index.map { |i| "#{4+i*2} 0 R" }.join(' ')}] >>"
      objects<<'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
      @pages.each_with_index do |stream,i|
        objects<<"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{W} #{H}] /Resources << /Font << /F1 3 0 R >> >> /Contents #{5+i*2} 0 R >>"
        objects<<"<< /Length #{stream.bytesize} >>\nstream\n#{stream}endstream"
      end
      out="%PDF-1.4\n".b; offsets=[0]
      objects.each_with_index { |obj,i| offsets<<out.bytesize; out<<"#{i+1} 0 obj\n".b<<obj.b<<"\nendobj\n".b }
      xref=out.bytesize; out<<"xref\n0 #{objects.size+1}\n0000000000 65535 f \n"
      offsets.drop(1).each { |v| out<<format('%010d 00000 n ',v)<<"\n" }
      out<<"trailer\n<< /Size #{objects.size+1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
      File.binwrite(path,out)
    end
  end

  module Export
    extend self
    def n(v); v.to_f.round(2); end
    def process_type(o)
      return 'GROOVE' if o[:kind]=='groove'
      raise "Unknown machining operation kind: #{o[:kind]}" unless o[:kind]=='drill'
      # These bore envelopes require a circular recess/pocket, not a pilot.
      # The workshop can instead choose the matching dedicated boring tool.
      pockets=%w[review-cup35 review-minifix-cam review-rafix20-housing review-screw-recess]
      pockets.include?(o[:recipe]) ? 'POCKET' : 'DRILL'
    end
    def op_layer(o)
      kind=o[:kind]=='groove' ? "GROOVE_W#{n([o[:w],o[:h]].min)}" : "#{process_type(o)}_D#{n(o[:diameter])}"
      "REVIEW_#{o[:face]}_#{kind}_Z#{n(o[:depth])}".tr('.','p')
    end
    def mapping(sheets)
      sheets.each_with_object({}) { |s,h| s[:placements].each { |at| h[at[:part]]=[s,at] } }
    end
    def machining_csv(path,parts)
      CSV.open(path,'wb') do |csv|
        csv << %w[Part Operation Kind Face Edge X_mm Y_mm Diameter_mm Width_mm Height_mm Depth_mm Recipe Status Process DXF_Layer]
        parts.each do |p|
          p[:operations].each { |o| csv << [p[:number],o[:id],o[:kind],o[:face],o[:edge],o[:x],o[:y],o[:diameter],o[:w],o[:h],o[:depth],o[:recipe],'REVIEW',process_type(o),op_layer(o)] }
        end
      end
    end
    def draw_part_dxf(d,p,transform,face:'A',label:true,label_detail:'compact')
      d.poly(p[:outline].map { |x,y| transform.call(x,y) },"CUT_#{face}_OUTSIDE_Z#{n(p[:t])}".tr('.','p'))
      p[:holes].each { |loop| d.poly(loop.map { |x,y| transform.call(x,y) },"CUT_#{face}_INSIDE_Z#{n(p[:t])}".tr('.','p')) }
      p[:operations].select { |o| o[:face]==face }.each do |o|
        if o[:kind]=='groove'
          d.poly(AJBoardKitchen.groove_outline(o).map { |x,y| transform.call(x,y) },op_layer(o))
        else
          x,y=transform.call(o[:x],o[:y]); d.circle(x,y,o[:diameter]/2,op_layer(o))
        end
      end
      [0,4].each { |off| AJBoardKitchen.edge_segments(p,off).each { |a,b,_,_| d.line(transform.call(*a),transform.call(*b),'NONCUT_EDGEBAND_DOUBLE') } }
      if label
        Annotations.layout(p,transform,face:face,detail:label_detail).each { |a| d.text(a[:text],a[:x],a[:y],a[:size],a[:kind]) }
      end
    end
    def part_dxfs(folder,parts,sketchup_labels:true,label_detail:'compact',dxf_class:DXF)
      FileUtils.mkdir_p(folder)
      parts.each do |p|
        %w[A B].each do |face|
          d=dxf_class.new(sketchup_labels:sketchup_labels); transform=face=='A' ? proc { |x,y| [x,y] } : proc { |x,y| [p[:w]-x,y] }
          draw_part_dxf(d,p,transform,face:face,label_detail:label_detail)
          d.text("#{p[:number]} #{p[:name]} | FACE #{face} | mm | REVIEW",0,-35,12,'NOTES')
          d.text("Core #{n(p[:w])} x #{n(p[:h])} x #{n(p[:t])}; B mirrored about local Y",0,-58,10,'NOTES')
          d.save(File.join(folder,"#{p[:number]}_#{face}.dxf"))
        end
        p[:operations].select { |o| o[:face]=='EDGE' }.group_by { |o| o[:edge] }.each do |edge,ops|
          d=dxf_class.new(sketchup_labels:sketchup_labels); d.poly(S.rectangle(p[:h],p[:t]),'NONCUT_EDGE_OUTLINE')
          ops.each { |o| d.circle(o[:y],p[:t]/2,o[:diameter]/2,op_layer(o)) }
          d.text("#{p[:number]} / #{p[:cabinet_id]} / #{p[:name]}",0,p[:t]+15,10,'PART_NAME')
          ops.group_by { |o| [o[:recipe],o[:diameter],o[:depth]] }.values.each_with_index do |group,i|
            o=group.first
            d.text("#{group.length}X #{Annotations.operation_name(o)} D#{n(o[:diameter])} Z#{n(o[:depth])}",0,-45-i*16,10,'MACHINING_LABEL')
          end
          d.text("#{p[:number]} EDGE #{edge} | X=part Y; Y=thickness | REVIEW",0,-25,10,'NOTES')
          d.save(File.join(folder,"#{p[:number]}_EDGE_#{edge}.dxf"))
        end
      end
    end
    def sheet_dxfs(folder,parts,sheets,sketchup_labels:true,label_detail:'compact',dxf_class:DXF)
      FileUtils.mkdir_p(folder); lookup=parts.to_h { |p| [p[:number],p] }
      sheets.each do |s|
        %w[A B].each do |face|
          d=dxf_class.new(sketchup_labels:sketchup_labels);d.poly(S.rectangle(s[:w],s[:h]),'NONCUT_SHEET_OUTLINE')
          s[:placements].each do |at|
            p=lookup.fetch(at[:part]); t=proc do |x,y|
              xx,yy=AJBoardKitchen.place_xy(p,at,x,y); [face=='B' ? s[:w]-xx : xx,yy]
            end
            draw_part_dxf(d,p,t,face:face,label_detail:label_detail)
          end
          d.text("#{s[:id]} #{s[:material]} #{n(s[:t])}mm FACE #{face} - REVIEW",0,s[:h]+40,22,'NOTES')
          d.text(face=='B' ? 'Whole sheet flip about Y; do not mirror again.' : 'Face A top view. See part EDGE files for horizontal drilling.',0,s[:h]+75,16,'NOTES')
          d.save(File.join(folder,"#{s[:id]}_#{face}.dxf"))
        end
      end
    end
    def sketchup_dxfs(folder,parts,sheets,label_detail:'compact')
      part_dxfs(File.join(folder,'parts'),parts,sketchup_labels:true,label_detail:label_detail)
      sheet_dxfs(File.join(folder,'sheets'),parts,sheets,sketchup_labels:true,label_detail:label_detail)
      File.write(File.join(folder,'READ_ME.txt'),"SKETCHUP VISUAL REVIEW - millimetres\nThese files have the same visible LINE labels as the main parts_dxf and sheets_dxf folders.\nCompact labels: part number, cabinet, name, core size and band sides/thickness. Full mode adds face machining text. All drill/groove geometry is always exported.\nNONCUT_LABEL_* layers are annotation geometry, never toolpaths.\nOptional CAD TEXT files are in cad_dxf/parts and cad_dxf/sheets.\nB views are already mirrored; do not mirror again. EB L/R/B/T always means local A sides.\n")
    end
    def dxf_sets(folder,parts,sheets,label_detail:'compact')
      # The main files must show labels when imported into SketchUp. TEXT-only
      # CAD files are an explicit alternative, never the default output.
      part_dxfs(File.join(folder,'parts_dxf'),parts,label_detail:label_detail)
      sheet_dxfs(File.join(folder,'sheets_dxf'),parts,sheets,label_detail:label_detail)
      part_dxfs(File.join(folder,'aspire_dxf','parts'),parts,label_detail:label_detail,dxf_class:AspireDXF)
      sheet_dxfs(File.join(folder,'aspire_dxf','sheets'),parts,sheets,label_detail:label_detail,dxf_class:AspireDXF)
      File.write(File.join(folder,'aspire_dxf','READ_ME.txt'),"ASPIRE IMPORT / R12 2D / MILLIMETRES\nSet the Aspire job to mm, then File > Import > Import Vectors.\nparts contains A, B and EDGE setups. sheets contains nested A/B setups.\nClosed POLYLINE outlines and grooves; CIRCLE drilling; visible LINE labels.\nAll NONCUT_* layers are reference geometry, not machining layers.\nCUT_A/B_OUTSIDE and CUT_A/B_INSIDE are separate profiles. REVIEW face DRILL, POCKET and GROOVE layers never mix process types; diameter/width and Z depth are in each name.\nThe B setup is already mirrored; do not mirror it again.\nR12 has no automatic insertion-unit metadata: verify the 100 mm calibration square.\nNative Aspire import still requires a user check.\n")
      part_dxfs(File.join(folder,'cad_dxf','parts'),parts,sketchup_labels:false,label_detail:label_detail)
      sheet_dxfs(File.join(folder,'cad_dxf','sheets'),parts,sheets,sketchup_labels:false,label_detail:label_detail)
      # Preserve the previous import paths for existing users.
      %w[parts sheets].each do |kind|
        target=File.join(folder,'sketchup_dxf',kind);FileUtils.mkdir_p(target)
        Dir.glob(File.join(folder,"#{kind}_dxf",'*.dxf')).each { |path| FileUtils.cp(path,target) }
      end
      File.write(File.join(folder,'sketchup_dxf','READ_ME.txt'),"Same visible-label DXFs as parts_dxf and sheets_dxf.\nLabels are LINE geometry on NONCUT_LABEL_* layers; exclude these layers from machining.\nOptional CAD TEXT files: cad_dxf/parts and cad_dxf/sheets.\n")
    end
    def table_pdf(path,job,sheets)
      pdf=PDF.new; locations=mapping(sheets); y=0
      title=proc do |subtitle|
        pdf.color(0.08,0.24,0.25);pdf.text('AJ / BOARD KITCHEN',28,35,17)
        pdf.text(subtitle,28,55,10);pdf.color(0.15,0.15,0.15)
        pdf.text('3048 mm | Core dimensions exclude edging | Workshop test',28,72,9)
        pdf.text('Part     Cabinet / description                       Cut W x H x T mm      Sheet     Band L/R/B/T',28,97,9)
        pdf.line(28,104,567,104); y=121
      end
      title.call('Bill of materials / one row per physical part')
      AJBoardKitchen.parts(job).each do |p|
        if y>770;pdf.page;title.call('Bill of materials / continued');end
        pdf.text(p[:number],28,y,9)
        pdf.text("#{p[:cabinet_id]} / #{p[:name]}"[0,39],73,y,8)
        dim=p[:kind]=='profile' ? "L #{n(p[:cut_length])}" : "#{n(p[:w])} x #{n(p[:h])} x #{n(p[:t])}"
        pdf.text(dim,310,y,8);pdf.text(locations[p[:number]]&.first&.dig(:id)||'BAR',437,y,8)
        pdf.text(%w[L R B T].map { |e| n((p[:edges]||{}).fetch(e,0)) }.join('/'),480,y,8)
        pdf.color(0.82,0.85,0.85);pdf.line(28,y+6,567,y+6,0.25);pdf.color(0.15,0.15,0.15);y+=19
      end
      pdf.page;title.call('Hardware quantities / editable review recipes')
      job[:cabinets].flat_map { |c| c[:hardware] }.group_by { |h| [h[:name],h[:recipe],h[:size]] }.each do |(name,recipe,size),items|
        if y>765;pdf.page;title.call('Hardware / continued');end
        pdf.text("#{items.sum { |h| h[:quantity] }} x #{name}",28,y,10)
        pdf.text("#{recipe} | #{size.map { |v| n(v) }.join(' x ')} mm",55,y+13,8);y+=33
      end
      pdf.page;title.call('Sheet and edgeband totals')
      sheets.group_by { |s| [s[:material],s[:t]] }.each do |(mat,t),ss|
        pdf.text("#{ss.length} sheets / #{mat} / #{n(t)} mm / #{n(ss[0][:w])} x #{n(ss[0][:h])}",28,y,10);y+=22
      end
      bands=Hash.new(0.0)
      AJBoardKitchen.panels(job).each { |p| AJBoardKitchen.edge_segments(p).each { |a,b,_,t| bands[[p[:material],t]]+=Math.hypot(a[0]-b[0],a[1]-b[1])/1000 } }
      y+=20
      bands.each { |(mat,t),m| pdf.text("#{mat} / #{t} mm band: #{m.round(2)} m net (add workshop waste)",28,y,10);y+=20 }
      y+=15
      job[:notes].each do |note|
        note.scan(/.{1,94}(?:\s|$)|.{1,94}/).each { |line| pdf.text(line.strip,28,y,9);y+=14 };y+=7
      end
      pdf.save(path)
    end
    def part_picture(pdf,p,x,y,w,h)
      scale=[w/p[:w],h/p[:h]].min
      tx=x+(w-p[:w]*scale)/2; ty=y+(h-p[:h]*scale)/2
      map=proc { |a| [tx+a[0]*scale,ty+(p[:h]-a[1])*scale] }
      pdf.color(0.14,0.22,0.23)
      ([p[:outline]]+p[:holes]).each { |poly| poly.each_with_index { |a,i| b=poly[(i+1)%poly.length];pdf.line(*map.call(a),*map.call(b),0.7) } }
      p[:operations].reject { |o| o[:face]=='EDGE' }.each { |o| operation_picture(pdf,o,proc { |a,b| map.call([a,b]) },scale) }
      # Fixed print-space separation keeps both edge lines legible on small stickers.
      [0,2.2/scale].each { |off| AJBoardKitchen.edge_segments(p,off).each { |a,b,_,_| pdf.line(*map.call(a),*map.call(b),1.0) } }
    end
    def operation_picture(pdf,o,map,scale)
      if o[:kind]=='groove'
        points=AJBoardKitchen.groove_outline(o)
        points.each_with_index { |a,i| pdf.line(*map.call(*a),*map.call(*points[(i+1)%4]),0.5) }
      else
        pdf.circle(*map.call(o[:x],o[:y]),[o[:diameter]*scale/2,0.5].max)
      end
    end
    def labels_pdf(path,job,sheets)
      pdf=PDF.new; locations=mapping(sheets)
      AJBoardKitchen.panels(job).each_with_index do |p,i|
        pdf.page if i>0 && i%8==0
        col=i%2;row=(i%8)/2;x=20+col*280;y=25+row*197
        pdf.color(0.65,0.7,0.7);pdf.rect(x,y,272,187)
        pdf.color(0.07,0.26,0.27);pdf.text("#{p[:number]}  /  #{p[:cabinet_id]}",x+10,y+21,15)
        pdf.text(p[:name][0,42],x+10,y+37,9)
        pdf.color(0.15,0.15,0.15)
        pdf.text("CUT #{n(p[:w])} x #{n(p[:h])} x #{n(p[:t])} mm / #{p[:material]}",x+10,y+52,8)
        part_picture(pdf,p,x+10,y+63,135,76)
        s,at=locations.fetch(p[:number]);sc=100.0/s[:w]
        pdf.color(0.7,0.73,0.73);pdf.rect(x+158,y+77,100,s[:h]*sc)
        s[:placements].each { |q| pdf.rect(x+158+q[:x]*sc,y+77+(s[:h]-q[:y]-q[:h])*sc,q[:w]*sc,q[:h]*sc) }
        pdf.color(0.12,0.52,0.48);pdf.rect(x+158+at[:x]*sc,y+77+(s[:h]-at[:y]-at[:h])*sc,at[:w]*sc,at[:h]*sc,fill:true)
        pdf.color(0.12,0.2,0.2);pdf.text("#{s[:id]} / A side location",x+158,y+69,8)
        pdf.text("X #{n(at[:x])} / Y #{n(at[:y])}",x+158,y+143,8)
        pdf.text("Band L/R/B/T: #{%w[L R B T].map { |e| (p[:edges]||{}).fetch(e,0) }.join('/')} mm",x+10,y+158,8)
        pdf.text('Double line = band. Picture = local A view.',x+10,y+172,8)
        pdf.text('REVIEW',x+222,y+172,7)
      end
      pdf.save(path)
    end
    def sheets_pdf(path,job,sheets)
      pdf=PDF.new; lookup=AJBoardKitchen.panels(job).to_h { |p| [p[:number],p] }
      sheets.each_with_index do |s,i|
        pdf.page if i>0
        pdf.color(0.08,0.25,0.25);pdf.text("#{s[:id]} / #{s[:material]} / #{s[:t]} mm",28,38,17)
        pdf.text('Face A overview / part IDs stay horizontal / dimensions in mm',28,60,9)
        scale=535.0/s[:w]; x=28;y=85
        pdf.color(0.4,0.45,0.45);pdf.rect(x,y,535,s[:h]*scale)
        s[:placements].each do |at|
          p=lookup[at[:part]]; tx=proc { |a,b| xx,yy=AJBoardKitchen.place_xy(p,at,a,b);[x+xx*scale,y+(s[:h]-yy)*scale] }
          ([p[:outline]]+p[:holes]).each { |poly| poly.each_with_index { |a,j| b=poly[(j+1)%poly.length];pdf.line(*tx.call(*a),*tx.call(*b)) } }
          [0,4].each { |off| AJBoardKitchen.edge_segments(p,off).each { |a,b,_,_| pdf.line(*tx.call(*a),*tx.call(*b),0.7) } }
          p[:operations].reject { |o| o[:face]=='EDGE' }.each { |o| operation_picture(pdf,o,tx,scale) }
          xx=x+(at[:x]+at[:w]/2)*scale; yy=y+(s[:h]-at[:y]-at[:h]/2)*scale
          pdf.color(0.05,0.17,0.17);pdf.text(p[:number],xx-9,yy+2,6);pdf.color(0.4,0.45,0.45)
        end
        yy=390
        s[:placements].each_slice(2) do |pair|
          pair.each_with_index { |at,j| p=lookup[at[:part]];pdf.text("#{p[:number]} #{p[:cabinet_id]} #{p[:name]}"[0,47],28+270*j,yy,8) }; yy+=17
        end
        pdf.text('Machining overview combines A/B marks. Use separate A/B and EDGE DXFs for setups.',28,803,8)
      end
      pdf.save(path)
    end
    def package(job,base)
      folder=File.join(base,"AJ_Board_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(2)}")
      FileUtils.mkdir_p(folder);sheets=AJBoardKitchen.nest(job);all=AJBoardKitchen.parts(job);panels=AJBoardKitchen.panels(job);loc=mapping(sheets)
      File.write(File.join(folder,'job.json'),JSON.pretty_generate(job));File.write(File.join(folder,'nesting.json'),JSON.pretty_generate(sheets))
      CSV.open(File.join(folder,'BOM.csv'),'wb') do |csv|
        csv << %w[Part Cabinet Name Quantity Material CutWidth_mm CutHeight_mm Thickness_mm FinishedWidth_mm FinishedHeight_mm Band_L Band_R Band_B Band_T Sheet X_mm Y_mm Rotated Grain]
        all.each do |p|
          s,at=loc[p[:number]];csv << [p[:number],p[:cabinet_id],p[:name],1,p[:material],p[:w],p[:h],p[:t],p[:finished_w],p[:finished_h],*%w[L R B T].map { |e| (p[:edges]||{}).fetch(e,0) },s&.dig(:id),at&.dig(:x),at&.dig(:y),at&.dig(:rotated),p[:grain]]
        end
      end
      machining_csv(File.join(folder,'machining.csv'),all)
      CSV.open(File.join(folder,'hardware.csv'),'wb') do |csv|
        csv << %w[Cabinet Hardware Quantity Recipe]
        job[:cabinets].each { |c| c[:hardware].group_by { |h| [h[:name],h[:recipe]] }.each { |(name,recipe),hs| csv << [c[:id],name,hs.sum { |h| h[:quantity] },recipe] } }
      end
      CSV.open(File.join(folder,'profiles.csv'),'wb') do |csv|
        csv << %w[Part Cabinet Profile CutLength_mm Quantity]
        all.select { |p| p[:kind]=='profile' }.each { |p| csv << [p[:number],p[:cabinet_id],p[:name],p[:cut_length],1] }
      end
      detail=job[:settings].fetch(:label_detail,'compact')
      dxf_sets(folder,panels,sheets,label_detail:detail)
      table_pdf(File.join(folder,'BOM.pdf'),job,sheets);labels_pdf(File.join(folder,'Part_Stickers.pdf'),job,sheets);sheets_pdf(File.join(folder,'Nested_Sheets.pdf'),job,sheets)
      File.write(File.join(folder,'READ_FIRST.txt'),"AJ BOARD KITCHEN - WORKSHOP TEST\n\n"+job[:notes].join("\n\n")+"\n\nEvery DXF is millimetres. Depth is encoded in each drill layer and machining.csv.\nA and B are separate setups; EDGE files are horizontal drilling setups.\nMain parts_dxf and sheets_dxf files include visible LINE labels for SketchUp.\nSketchUp skips CAD TEXT. The review files use LINE lettering on NONCUT_LABEL_* layers (never toolpaths).\nAspire compatibility: aspire_dxf/parts and aspire_dxf/sheets (R12, closed outlines; set job to mm). DRILL / POCKET / GROOVE / CUT have separate layers; all NONCUT layers are references only.\nOptional CAD TEXT: cad_dxf/parts and cad_dxf/sheets. Labels stay horizontal; double lines identify banded sides.\nEB L/R/B/T means local A sides before rotation or B mirroring. D=diameter, W=groove width, Z=depth.\nPDF stickers: print at 100%, A4, cut along 2-column / 4-row grid.\nNesting uses grain-constrained shelf packing, not a claimed optimum.\n")
      folder
    end
  end
end
