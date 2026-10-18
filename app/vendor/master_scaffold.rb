# frozen_string_literal: true
# Cabinex Master Studio — independent consolidation, 2026-09-13.
# All engineering coordinates are numeric millimetres. SketchUp inches exist
# only in Adapter. No source-engine loads, remote evaluation or token bypass.
require 'json'
require 'csv'
require 'digest'
require 'fileutils'
require 'securerandom'
require 'stringio'

module AJBoardScaffold
  VERSION = '1.0.0-dev' unless const_defined?(:VERSION)
  HOME = File.expand_path(__dir__) unless const_defined?(:HOME)
  DICT = 'AJBoardScaffold' unless const_defined?(:DICT)
  MODES = %w[board aluminum aluminum_economy hybrid].freeze unless const_defined?(:MODES)
  X = [1,0,0].freeze unless const_defined?(:X)
  Y = [0,1,0].freeze unless const_defined?(:Y)
  Z = [0,0,1].freeze unless const_defined?(:Z)
  NY = [0,-1,0].freeze unless const_defined?(:NY)
  NZ = [0,0,-1].freeze unless const_defined?(:NZ)
  extend self
  @catalogue=nil # Refresh family definitions when this development file is reloaded.

  module Math3
    extend self
    def add(a,b); a.zip(b).map { |x,y| x+y }; end
    def scale(a,s); a.map { |x| x*s }; end
    def dot(a,b); a.zip(b).sum { |x,y| x*y }; end
    def cross(a,b); [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]; end
    def local(p,q); add(p[:o],add(scale(p[:u],q[0]),add(scale(p[:v],q[1]),scale(p[:n],q[2])))); end
    def rotate(p,deg)
      a=deg*Math::PI/180; [p[0]*Math.cos(a)-p[1]*Math.sin(a),p[0]*Math.sin(a)+p[1]*Math.cos(a),p[2]]
    end
    def world(p,pose); add(rotate(p,pose[3]),pose[0,3]); end
    def area(poly); poly.each_with_index.sum { |a,i| b=poly[(i+1)%poly.size]; a[0]*b[1]-b[0]*a[1] }.abs/2.0; end
    def inside?(p,poly)
      # Boundary counts as inside; used for machining and shape verification.
      poly.each_with_index do |a,i|
        b=poly[(i+1)%poly.size]; ab=[b[0]-a[0],b[1]-a[1]]; ap=[p[0]-a[0],p[1]-a[1]]
        return true if (ab[0]*ap[1]-ab[1]*ap[0]).abs<1e-6 && dot(ap,ab)>=-1e-6 && dot(ap,ab)<=dot(ab,ab)+1e-6
      end
      hit=false; j=poly.size-1
      poly.each_index do |i|
        a,b=poly[i],poly[j]
        hit=!hit if ((a[1]>p[1])!=(b[1]>p[1])) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]
        j=i
      end
      hit
    end
    def overlap?(a,b,tol=0.1)
      [a,b].all? do |poly|
        poly.each_with_index.all? do |p,i|
          q=poly[(i+1)%poly.size]; axis=[p[1]-q[1],q[0]-p[0]]
          len=Math.sqrt(dot(axis,axis)); next true if len<1e-9
          av=a.map { |v| dot(v,axis)/len }; bv=b.map { |v| dot(v,axis)/len }
          av.max>bv.min+tol && bv.max>av.min+tol
        end
      end
    end
  end

  def rectangle(w,h); [[0.0,0.0],[w.to_f,0.0],[w.to_f,h.to_f],[0.0,h.to_f]]; end
  def deep(value); Marshal.load(Marshal.dump(value)); end
  def safe_name(s); s.to_s.gsub(/[^A-Za-z0-9_.-]/,'_'); end
  def write_json(path,obj); FileUtils.mkdir_p(File.dirname(path)); File.write(path,JSON.pretty_generate(obj)); end
  def log(message)
    FileUtils.mkdir_p(File.join(HOME,'output'))
    File.open(File.join(HOME,'output','studio.log'),'a') { |f| f.puts "#{Time.now.iso8601 rescue Time.now} #{message}" }
    puts "[Cabinex Master] #{message}"
    Sketchup.status_text="Cabinex Master: #{message}" if defined?(Sketchup)
  end

  # Families are implemented construction recipes, not empty catalogue aliases.
  def catalogue
    @catalogue ||= begin
      rows=[
        ['base_single','Base / single door',600,720,560,:single],
        ['base_double','Base / paired doors',900,720,560,:double],
        ['base_open','Base / open shelves',600,720,560,:open],
        ['base_drawers_2','Base / two drawers',900,720,560,:drawers2],
        ['base_drawers_3','Base / three drawers',900,720,560,:drawers3],
        ['base_drawers_4','Base / four drawers',600,720,560,:drawers4],
        ['base_gola','Base / L + C Gola drawers',900,720,560,:gola],
        ['base_sink','Base / sink and service space',900,720,560,:sink],
        ['base_oven','Base / oven housing',600,720,560,:oven],
        ['base_dishwasher','Dishwasher / framed opening',600,720,560,:dishwasher],
        ['base_pullout','Base / purposeful bottle pullout',300,720,560,:pullout],
        ['base_tray','Base / tray dividers',450,720,560,:tray],
        ['base_waste','Base / waste pullout',600,720,560,:waste],
        ['blind_left','Blind corner / blind at left',1200,720,560,:blind_left],
        ['blind_right','Blind corner / blind at right',1200,720,560,:blind_right],
        ['corner_diagonal','Corner / diagonal opening',1000,720,1000,:diagonal],
        ['corner_l','Corner / L return and two doors',1000,720,1000,:l_corner],
        ['wall_single','Wall / single door',600,720,330,:single],
        ['wall_double','Wall / paired doors',900,720,330,:double],
        ['wall_blind_left','Wall corner / blind at left',850,720,330,:blind_left],
        ['wall_blind_right','Wall corner / blind at right',850,720,330,:blind_right],
        ['wall_glass','Wall / glass display',900,900,330,:glass],
        ['wall_open','Wall / open shelves',600,720,330,:open],
        ['wall_lift','Wall / lift-up front',900,360,330,:lift],
        ['wall_bifold','Wall / articulated bifold front',900,720,330,:bifold],
        ['wall_hood','Wall / hood recess',900,720,330,:hood],
        ['wall_wine','Wall / wine cells',600,720,330,:wine],
        ['wall_plate','Wall / plate rack',600,720,330,:plate],
        ['top_bulkhead','Top / lift-up bulkhead',900,360,580,:lift],
        ['tall_pantry','Tall / shelved pantry',600,2100,580,:pantry],
        ['tall_split','Tall / divided pantry',900,2100,580,:split],
        ['tall_oven_micro','Tall / oven and microwave tower',600,2100,580,:appliance_tower],
        ['tall_fridge','Tall / refrigerator housing',900,2100,650,:fridge],
        ['tall_space','Tall / internal pullout drawers',600,2100,580,:space_tower],
        ['island_storage','Island / double-sided storage',1200,720,1100,:island],
        ['island_seating','Island / seating overhang',1200,720,560,:seating],
        ['wardrobe_hanging','Wardrobe / full hanging',900,2300,600,:hanging],
        ['wardrobe_double_hang','Wardrobe / double hanging',900,2300,600,:double_hang],
        ['wardrobe_combo','Wardrobe / hanging + drawers',1200,2300,600,:robe_combo],
        ['wardrobe_shelves','Wardrobe / adjustable shelves',900,2300,600,:robe_shelves],
        ['wardrobe_shoes','Wardrobe / shoe shelves',900,2300,600,:shoes],
        ['wardrobe_trousers','Wardrobe / trouser pullout',900,2300,600,:trousers],
        ['wardrobe_open','Wardrobe / open dressing unit',1200,2300,600,:robe_open],
        ['wardrobe_sliding_2','Wardrobe / two sliding doors',1800,2300,650,:sliding2],
        ['wardrobe_sliding_3','Wardrobe / three sliding doors',2400,2300,650,:sliding3],
        ['wardrobe_mirror','Wardrobe / framed mirror doors',900,2300,600,:mirror],
        ['face_frame','Cabinet / solid face frame',900,720,560,:face_frame],
        ['shaker','Cabinet / five-piece shaker doors',900,720,560,:shaker]
      ]
      rows.map { |id,name,w,h,d,recipe| {id:id,name:name,w:w.to_f,h:h.to_f,d:d.to_f,recipe:recipe} }.freeze
    end
  end

  # Planning never calls Numeric#mm. Widths close in 0.01 mm integer ticks.
  module Planner
    extend self
    def divide(length,min:400,max:600,target:500)
      raise ArgumentError,'Span must be finite and positive' unless length.is_a?(Numeric) && length.finite? && length>0
      length=length.to_f
      lo=(length/max).ceil; hi=(length/min).floor
      raise ArgumentError,"No useful cabinet partition for #{length.round(2)} mm (#{min}–#{max})" if hi<lo
      count=(lo..hi).min_by { |n| [(length/n-target).abs,n] }
      ticks=(length*100).round; q,r=ticks.divmod(count)
      # Distribute rounding symmetrically without changing the run length.
      widths=Array.new(count,q); order=(0...count).sort_by { |i| [(i-(count-1)/2.0).abs,i] }
      order.first(r).each { |i| widths[i]+=1 }
      widths.map { |x| x/100.0 }
    end
    def subtract(span,blocked)
      intervals=[span]
      blocked.sort.each do |a,b|
        raise ArgumentError,'Invalid obstruction interval' unless b>a
        intervals=intervals.flat_map { |l,r| b<=l || a>=r ? [[l,r]] : [[l,[a,r].min],[[b,l].max,r]].select { |x,y| y-x>0.01 } }
      end
      intervals
    end
    def opening_intervals(openings,wall,z0,z1)
      openings.select { |o| o[:wall]==wall && o[:sill]<z1 && o[:sill]+o[:height]>z0 }.map { |o| [o[:x]-o.fetch(:clearance,25),o[:x]+o[:width]+o.fetch(:clearance,25)] }
    end
    def fill(span,anchors:[],min:400,max:600)
      l,r=span; sorted=anchors.sort_by { |a| a[:x] }
      sorted.each_with_index do |a,i|
        raise ArgumentError,'Locked unit lies outside its usable span' if a[:x]<l-0.01 || a[:x]+a[:w]>r+0.01
        raise ArgumentError,'Locked appliances overlap' if i>0 && sorted[i-1][:x]+sorted[i-1][:w]>a[:x]+0.01
      end
      output=[]; cursor=l
      (sorted+[ {x:r,w:0,type:nil} ]).each do |a|
        gap=a[:x]-cursor
        if gap>0.01
          if gap<=50
            output << {x:cursor,w:gap,type:'filler',purpose:'installation clearance'}
          else
            begin
              divide(gap,min:min,max:max).each { |w| output << {x:cursor,w:w,type:'base_single'}; cursor+=w }
            rescue ArgumentError
              # A useful paired-door cabinet can bridge a span which would
              # otherwise become two narrow carcasses or an excessive filler.
              raise unless gap>=650 && gap<=1200
              output << {x:cursor,w:gap,type:'base_double'}; cursor+=gap
            end
          end
        end
        output << a if a[:type]; cursor=a[:x]+a[:w]
      end
      output
    end
    def upper_from_base(base,blocked:[])
      base.reject { |b| b[:type]=='filler' || b[:type].start_with?('tall_') }.flat_map do |b|
        spans=subtract([b[:x],b[:x]+b[:w]],blocked)
        spans.flat_map do |l,r|
          # Do not insert a slit cabinet beside a window. A short remainder is
          # deliberately left open and recorded by the kitchen report.
          next [] if r-l<300
          count=((r-l)/600.0).ceil; w=(r-l)/count
          Array.new(count) { |i| {x:l+i*w,w:w,type:b[:type]=='base_oven' ? 'wall_hood' : 'wall_single',base_boundary:[b[:x],b[:x]+b[:w]]} }
        end
      end
    end
    def audit_run(length,units,allowed:[])
      coverage=units.map { |u| [u[:x],u[:x]+u[:w]] }+allowed.map { |a| a[:span] }
      gaps=subtract([0,length],coverage)
      overlaps=units.sort_by { |u| u[:x] }.each_cons(2).filter_map do |a,b|
        {left:a[:type],right:b[:type],amount:a[:x]+a[:w]-b[:x]} if a[:x]+a[:w]>b[:x]+0.01
      end
      {gaps:gaps,overlaps:overlaps,ok:gaps.empty? && overlaps.empty?}
    end
    def close_run(length,units,allowed:[],upper:false)
      result=AJBoardScaffold.deep(units); attempts=0
      loop do
        audit=audit_run(length,result,allowed:allowed)
        raise ArgumentError,'Overlapping cabinets in run repair' unless audit[:overlaps].empty?
        return [result.sort_by { |u| u[:x] },audit.merge(redivision_attempts:attempts)] if audit[:ok]
        raise ArgumentError,"Run cannot close after #{attempts} redivisions: #{audit[:gaps]}" if attempts>=24
        l,r=audit[:gaps].first; attempts+=1
        if r-l<=50
          result << {x:l,w:r-l,type:'filler',purpose:'scribed closure'}; next
        end
        neighbours=result.select do |u|
          %w[base_single base_double base_drawers_2 base_drawers_3 base_drawers_4 base_gola wall_single wall_double].include?(u[:type]) &&
            ((u[:x]+u[:w]-l).abs<0.01 || (u[:x]-r).abs<0.01)
        end
        repaired=false
        [[],*neighbours.map { |u| [u] },neighbours].uniq.each do |borrowed|
          a=([l]+borrowed.map { |u| u[:x] }).min; b=([r]+borrowed.map { |u| u[:x]+u[:w] }).max
          begin
            widths=divide(b-a,min:upper ? 300 : 400,max:600)
            result-=borrowed; x=a
            widths.each { |w| result << {x:x,w:w,type:upper ? 'wall_single' : 'base_single'}; x+=w }
            repaired=true; break
          rescue ArgumentError
          end
        end
        raise ArgumentError,"Unexplained #{(r-l).round(2)} mm gap at #{l.round(2)} mm; move a locked appliance or change the room division." unless repaired
      end
    end
    def upper_plan(spans,base)
      spans.flat_map do |l,r|
        raise ArgumentError,"Only #{(r-l).round} mm remains beside an upper opening; adjust the opening clearance or cabinet boundary." if r-l<300 && r-l>50
        next [{x:l,w:r-l,type:'filler',purpose:'upper scribe'}] if r-l<=50
        seams=([l,r]+base.flat_map { |u| [u[:x],u[:x]+u[:w]] }.select { |x| x>l+0.01 && x<r-0.01 }).uniq.sort
        intervals=seams.each_cons(2).to_a
        while intervals.size>1 && (i=intervals.index { |a,b| b-a<300 })
          j=i==0 ? 0 : i-1; intervals[j,2]=[[intervals[j][0],intervals[j+1][1]]]
        end
        intervals.flat_map do |a,b|
          count=((b-a)/600.0).ceil; w=(b-a).to_f/count
          Array.new(count) do |i|
            x=a+i*w; owner=base.find { |u| x+w/2>=u[:x] && x+w/2<u[:x]+u[:w] }
            {x:x,w:w,type:owner && owner[:type]=='base_oven' ? 'wall_hood' : 'wall_single',base_boundary:[a,b]}
          end
        end
      end
    end
    def corner_candidates(a,b,depth:560,access:450,clearance:65)
      blind=depth+clearance; owner=blind+access
      [{owner:'A',take_a:owner,take_b:blind,blind:'right'}, {owner:'B',take_a:blind,take_b:owner,blind:'left'}].select { |c| c[:take_a]<=a && c[:take_b]<=b }
    end
    def choose_corner(a,b,**opts)
      choices=corner_candidates(a,b,**opts)
      raise ArgumentError,'Corner cannot provide the minimum accessible opening' if choices.empty?
      choices.min_by { |c| [(a-c[:take_a]-(b-c[:take_b])).abs,c[:owner]] }
    end
  end

  class Cabinet
    attr_reader :data
    def initialize(type,mode:'board',w:nil,h:nil,d:nil,id:nil,pose:[0,0,0,0],options:{})
      row=AJBoardScaffold.catalogue.find { |r| r[:id]==type.to_s }
      raise ArgumentError,"Unknown cabinet family: #{type}" unless row
      raise ArgumentError,"Unknown construction mode: #{mode}" unless MODES.include?(mode.to_s)
      @data={schema:1,id:id || SecureRandom.hex(5),type:type.to_s,name:row[:name],mode:mode.to_s,w:(w||row[:w]).to_f,h:(h||row[:h]).to_f,d:(d||row[:d]).to_f,pose:pose.map(&:to_f),options:options,parts:[],hardware:[],motions:[],warnings:[]}
      @w,@h,@d=@data.values_at(:w,:h,:d); @recipe=row[:recipe]
      raise ArgumentError,'Dimensions must be finite and positive' unless [@w,@h,@d].all? { |v| v.finite? && v>0 }
      raise ArgumentError,'Cabinet is too narrow, shallow or short for this construction' if @w<250 || @d<180 || @h<250
      raise ArgumentError,'Oversized cabinet; split into modules' if @w>2600 || @h>2800 || @d>1400
      @alu=%w[aluminum aluminum_economy].include?(mode.to_s)
      @hybrid=mode.to_s=='hybrid'; @t=@alu ? 25.4 : 18.0
      @wall=type.to_s.start_with?('wall_','top_'); @robe=type.to_s.start_with?('wardrobe_')
      @plinth=@wall ? 0.0 : 100.0; @z=@plinth
      @gola=@recipe==:gola || (options[:front_system]=='gola' && !@wall && @h<=900 && [:single,:double,:drawers2,:drawers3,:drawers4,:sink,:blind_left,:blind_right,:pullout,:waste].include?(@recipe))
      @gola_gap=Float(options.fetch(:finger_gap,25))
      raise ArgumentError,'Finger clearance must be between 20 and 40 mm' if @gola && !@gola_gap.between?(20,40)
      @data[:front_system]=@gola ? 'gola' : 'handled'
      @front_y=-@d; @material=@alu ? 'ACP' : 'Carcass'; @pt=@alu ? 3.0 : 18.0
      build
      validate!
    end
    def parts; @data[:parts]; end
    def hardware; @data[:hardware]; end
    def panel(name,w,h,t,o,u=X,v=Y,n=Z,material:'Carcass',outline:nil,motion:nil,holes:[],edge_band:nil,grain:nil)
      raise ArgumentError,"Non-positive part #{name}" if [w,h,t].any? { |x| !x.finite? || x<=0 }
      p={id:"#{@data[:id]}-P#{parts.size+1}",name:name,kind:'panel',w:w.to_f,h:h.to_f,t:t.to_f,o:o,u:u,v:v,n:n,outline:outline||AJBoardScaffold.rectangle(w,h),holes:holes,material:material,motion:motion,grain:grain || (%w[Glass ACP Mirror].include?(material) ? 'none' : w>h ? 'u' : 'v'),edge_band:edge_band,operations:[]}
      parts << p; p
    end
    def profile(name,length,o,u,v,n,section:'frame',motion:nil,miter:false)
      outer,inner=AJBoardScaffold.profile_section(section,@data[:mode])
      p=panel(name,outer.map(&:first).max-outer.map(&:first).min,outer.map(&:last).max-outer.map(&:last).min,length,o,u,v,n,material:section.start_with?('gola') ? 'Graphite' : 'Aluminum',outline:outer,motion:motion,holes:inner)
      p.merge!(kind:'profile',section:section,cut_length:length,stock_length:6400.0,miter_start:miter ? 45 : 0,miter_end:miter ? 45 : 0,grain:'none')
      p
    end
    def hw(name,o,size:[20,20,20],kind:'box',axis:Z,motion:nil,quantity:1,recipe:'illustration')
      h={id:"#{@data[:id]}-H#{hardware.size+1}",name:name,o:o,size:size,kind:kind,axis:axis,motion:motion,quantity:quantity,recipe:recipe}
      hardware << h; h
    end
    def motion(name,kind,pivot,hand:1,travel:90,parent:nil)
      id="#{@data[:id]}-M#{@data[:motions].size+1}"
      @data[:motions] << {id:id,name:name,kind:kind,pivot:pivot,hand:hand,travel:travel,parent:parent}; id
    end
    def drill(p,x,y,dia,depth,face:'A',tool:'drill',recipe:'generic',edge:nil)
      p[:operations] << {id:"#{p[:id]}-O#{p[:operations].size+1}",kind:'drill',x:x.to_f,y:y.to_f,diameter:dia.to_f,depth:depth.to_f,face:face,tool:tool,recipe:recipe,edge:edge,status:'engineering_template'}
    end
    def shelf(z,name='Shelf',x:@t,w:@w-2*@t,depth:@d-40,motion:nil)
      panel(name,w,depth,@alu ? 12.0 : 18.0,[x,-@d+18,z],X,Y,Z,material:@alu ? 'ShelfBoard' : 'Carcass',motion:motion)
    end
    def beam_x(name,x,y,z,len)
      profile(name,len,[x,y,z],Y,Z,X)
    end
    def carcass
      return angled_carcass if [:diagonal,:l_corner].include?(@recipe)
      if @alu
        q=@t; dep=@data[:mode]=='aluminum_economy' ? 25.4 : 38.1
        [0,@w-q].each_with_index do |x,i|
          [-@d,-dep].each_with_index { |y,j| profile("Upright #{i+1}.#{j+1}",@h,[x,y,@z],X,Y,Z) }
        end
        rail_h=@data[:mode]=='aluminum_economy' ? 25.4 : 38.1
        [@z,@z+@h-rail_h].each do |z|
          [-@d,-dep].each { |y| profile('Width rail',@w-2*q,[q,y,z],Y,Z,X) }
          [0,@w-q].each { |x| profile('Depth rail',@d-2*dep,[x,-@d+dep,z],X,Z,Y) }
        end
        panel('Left ACP infill',@d-2*dep,@h-2*q,3,[3,-@d+dep,@z+q],Y,Z,X,material:'ACP')
        panel('Right ACP infill',@d-2*dep,@h-2*q,3,[@w-6,-@d+dep,@z+q],Y,Z,X,material:'ACP')
        back_panels(q,@h-2*q,3,-3,@z+q,'Back ACP infill','ACP') unless [:sink,:oven,:fridge,:dishwasher].include?(@recipe)
        # Captive floor: 12 mm structural board supported by the four rails.
        shelf(@z+rail_h,'Supported floor',depth:@d-dep-18)
        8.times { |i| hw('Frame angle connector',[(i%2)*(@w-q),i%4<2 ? -@d+dep : -dep,@z+(i<4 ? q : @h-q)],size:[20,20,20],recipe:'frame-angle-template') }
      else
        side_outline=side_shape
        @sides=[panel('Left side',@d,@h,18,[0,-@d,@z],Y,Z,X,outline:side_outline,edge_band:'front:1mm'),panel('Right side',@d,@h,18,[@w-18,-@d,@z],Y,Z,X,outline:side_outline,edge_band:'front:1mm')]
        unless @recipe==:dishwasher
          @floor=panel('Bottom',@w-36,@d-18,18,[18,-@d,@z],material:'Carcass',edge_band:'front:1mm')
        end
        if @wall || @robe || @h>1000
          @top=panel('Top',@w-36,@d-18,18,[18,-@d,@z+@h-18],edge_band:'front:1mm')
        else
          front_y=@gola ? -@d+30 : -@d
          @top=panel('Front stretcher',@w-36,80,18,[18,front_y,@z+@h-18])
          panel('Rear stretcher',@w-36,80,18,[18,-98,@z+@h-18])
        end
        back_panels(18,@h-36,8,-10,@z+18,'Back','Back') unless [:sink,:oven,:fridge,:dishwasher].include?(@recipe)
        board_joints
      end
      feet unless @wall
    end
    def back_panels(inset,height,thickness,y,z,name,material)
      count=@recipe==:sliding3 ? 3 : @recipe==:sliding2 ? 2 : ((@w-2*inset)/1200.0).ceil
      # Seams coincide with wardrobe bay dividers, so no full-width 2.4 m x
      # 2.3 m sheet is silently sent to a 2440 x 1220 stock nest.
      boundaries=[inset]+(1...count).map { |i| @w*i/count.to_f }+[@w-inset]
      boundaries.each_cons(2).with_index do |(l,r),i|
        panel(count==1 ? name : "#{name} bay #{i+1}",r-l,height,thickness,[l,y,z],X,Z,NY,material:material,grain:material=='ACP' ? 'none' : 'v')
      end
      boundaries[1...-1].each do |x|
        hw('Back seam support strip',[x-22.5,y-7,z+25],size:[45,4,height-50],recipe:'back-seam-support')
      end
    end
    def side_shape
      return nil unless @gola
      points=[[0,0],[@d,0],[@d,@h],[30,@h],[30,@h-59],[0,@h-59]]
      gola_centres.reverse_each { |zc| points.concat([[0,zc+36.75],[30,zc+36.75],[30,zc-36.75],[0,zc-36.75]]) }
      points
    end
    def gola_count
      @recipe==:gola ? 2 : @recipe.to_s.start_with?('drawers') ? @recipe.to_s[-1].to_i : 0
    end
    def gola_front_height(count)
      (@h-@gola_gap-3-(count-1)*@gola_gap)/count.to_f
    end
    def gola_centres
      count=gola_count; return [] if count<2
      fh=gola_front_height(count)
      (1...count).map { |i| 3+i*fh+(i-1)*@gola_gap+@gola_gap/2.0 }
    end
    def gola_profiles
      return unless @gola
      @data[:gola]={finger_gap:@gola_gap,top_z:@z+@h,centres:gola_centres.map { |z| z+@z },split:'equal'}
      return if @data[:options][:defer_run_parts]
      profile('L Gola / undertop',@w,[0,-@d,@z+@h-56.5],Y,Z,X,section:'gola_l')
      gola_centres.each { |z| profile('C Gola / middle',@w,[0,-@d,@z+z-36.5],Y,Z,X,section:'gola_c') }
    end
    def board_joints
      return unless @sides && @floor
      connector=@data[:options].fetch(:joinery,'minifix').to_s
      return screw_joints if connector=='screw'
      raise ArgumentError,'OVVO requires its exact product drawing and machining recipe; no substitute drilling is generated.' if connector=='ovvo'
      raise ArgumentError,"Unsupported joinery #{connector}" unless connector=='minifix'
      # Explicit generic cam/bolt set: configurable engineering template, not
      # a claim that every Minifix SKU uses the same drilling distances.
      [@floor,@top].compact.each do |p|
        ys=p[:h]>150 ? [50,p[:h]-50] : [p[:h]/2.0]
        ys.each do |y|
          [34,p[:w]-34].each_with_index do |x,side|
            drill(p,x,y,15,12,face:'B',tool:'cam15',recipe:'generic-minifix-15-B34')
            # The edge bore and the bolt pilot on its mating side share a joint.
            edge=side==0 ? 'LEFT' : 'RIGHT'
            drill(p,side==0 ? 0 : p[:w],y,8,34,face:'EDGE',edge:edge,tool:'edge8',recipe:'generic-minifix-15-B34')
            s=@sides[side]; wp=Math3.local(p,[side==0 ? 0 : p[:w],y,p[:t]/2])
            sy=wp[1]+@d; sz=wp[2]-@z
            drill(s,sy,sz,5,12,face:side==0 ? 'B' : 'A',tool:'pilot5',recipe:'generic-minifix-bolt')
            hw('Minifix cam 15',Math3.local(p,[x,y,p[:t]-12]),size:[15,12,15],kind:'cylinder',axis:p[:n],recipe:'generic-minifix-15-B34')
            hw('Minifix bolt',wp,size:[5,34,5],kind:'cylinder',axis:side==0 ? X : [-1,0,0],recipe:'generic-minifix-bolt')
          end
        end
      end
      @sides.each_with_index do |s,i|
        [37,@d-37].each do |row|
          (128..(@h-100).floor).step(32) { |z| drill(s,row,z,5,12,face:i==0 ? 'B' : 'A',tool:'shelf5',recipe:'32mm-shelf-system') }
        end unless @gola || [:sink,:oven,:dishwasher].include?(@recipe)
      end
    end
    def screw_joints
      [@floor,@top].compact.each do |p|
        ys=p[:h]>150 ? [50,p[:h]-50] : [p[:h]/2.0]
        ys.each do |y|
          @sides.each_with_index do |s,i|
            edge=i==0 ? 'LEFT' : 'RIGHT'; wp=Math3.local(p,[i==0 ? 0 : p[:w],y,p[:t]/2])
            sy=wp[1]+@d; sz=wp[2]-@z; face=i==0 ? 'A' : 'B'
            drill(s,sy,sz,5.5,18,face:face,tool:'clearance5p5',recipe:'generic-screw-5x50')
            drill(s,sy,sz,9,2,face:face,tool:'head9',recipe:'generic-screw-5x50')
            drill(p,i==0 ? 0 : p[:w],y,3,32,face:'EDGE',edge:edge,tool:'pilot3',recipe:'generic-screw-5x50')
            o=[i==0 ? 0 : @w,wp[1],wp[2]]; axis=i==0 ? X : [-1,0,0]
            hw('Screw 5 x 50',o,size:[5,50,5],kind:'cylinder',axis:axis,recipe:'generic-screw-5x50')
            hw('Screw head',o,size:[9,2,9],kind:'cylinder',axis:axis,recipe:'generic-screw-5x50')
          end
        end
      end
    end
    def feet
      count=(@w/900.0).ceil+1
      count.times do |i|
        x=60+(@w-120)*i/(count-1).to_f
        [-@d+60,-60].each do |y|
          hw('Adjustable foot',[x,y,0],size:[38,100,38],kind:'cylinder',recipe:'adjustable-foot')
        end
      end
      panel('Recessed plinth',@w,95,16,[0,-@d+55,0],X,Z,NY,material:'Graphite') unless @data[:options][:defer_run_parts]
    end
    def handle(x,y,z,w,m)
      # Real folded finger pull, plus posts for the bar-handle choice.
      profile('Finger pull', [w-70,320].min,[x+35,y-18,z],Y,Z,X,section:'handle',motion:m)
    end
    def front(x,z,w,h,hand:1,style:nil,kind:'hinge',travel:nil,name:'Door',parent:nil,y:@front_y)
      raise ArgumentError,'Impractical front' if w<180 || h<100
      raise ArgumentError,'A hinged leaf over 650 mm must be divided into paired fronts.' if kind=='hinge' && w>650
      style ||= @alu || @hybrid ? 'sash' : 'slab'
      pivot=[hand==1 ? x : x+w,y,z]
      pivot=[x,y,z+h] if ['lift','fold'].include?(kind)
      m=motion(name,kind,pivot,hand:hand,travel:travel || (kind=='drawer' ? [@d-100,450].min : 95),parent:parent)
      if ['sash','glass','mirror'].include?(style)
        profile('Sash bottom / mitred',w,[x,y,z],Z,NY,X,section:'sash',motion:m,miter:true)
        profile('Sash top / mitred',w,[x,y,z+h],NZ,NY,X,section:'sash',motion:m,miter:true)
        profile('Sash left / mitred',h,[x,y,z],X,NY,Z,section:'sash',motion:m,miter:true)
        profile('Sash right / mitred',h,[x+w,y,z],[-1,0,0],NY,Z,section:'sash',motion:m,miter:true)
        material=style=='mirror' ? 'Mirror' : style=='glass' ? 'Glass' : 'Front'
        panel('Sash infill',w-14,h-14,4,[x+7,y-7,z+7],X,Z,NY,material:material,motion:m)
        # Profile hinges require the matching profile-specific insert. Do not
        # drill a 35 mm board cup into a hollow extrusion.
        [100,h-100].uniq.each { |hz| hw('Sash hinge + insert',[hand==1 ? x+15 : x+w-15,y+2,z+hz],size:[25,18,45],motion:m,recipe:'sash-hinge-template') } if kind=='hinge'
      elsif style=='shaker'
        [x,x+w-65].each { |xx| panel('Shaker stile',65,h,20,[xx,y,z],X,Z,NY,material:'Front',motion:m) }
        [z,z+h-65].each { |zz| panel('Shaker rail',w-130,65,20,[x+65,y,zz],X,Z,NY,material:'Front',motion:m) }
        panel('Shaker inset',w-130,h-130,8,[x+65,y-6,z+65],X,Z,NY,material:'Front',motion:m)
      else
        p=panel(name,w,h,18,[x,y,z],X,Z,NY,material:'Front',motion:m,edge_band:'all:1mm')
        if kind=='hinge'
          n=h>1800 ? 4 : h>1000 ? 3 : 2
          n.times do |i|
            hz=100+(h-200)*i/(n-1).to_f; hx=hand==1 ? 22.5 : w-22.5
            drill(p,hx,hz,35,13,face:'A',tool:'hinge35',recipe:'generic-cup-35')
            hw('Concealed hinge cup',[x+hx,y,z+hz],size:[35,13,35],kind:'cylinder',axis:NY,motion:m,recipe:'generic-cup-35')
            hw('Hinge arm',[hand==1 ? x : x+w-20,y,z+hz-7],size:[20,45,14],recipe:'generic-hinge-arm')
          end
        end
      end
      handle(x,y,z+h-35,w,m) unless @gola || kind=='slide'
      @data[:motions].last[:front]={x:x,y:y,z:z,w:w,h:h} if @data[:motions].last[:id]==m
      m
    end
    def doors(z:@z+1.5,h:@h-3,x:1.5,w:@w-3,style:nil,count:nil)
      h=[h,@z+@h-@gola_gap-z].min if @gola
      count ||= (w/600.0).ceil
      fw=(w-(count-1)*3)/count
      count.times { |i| front(x+i*(fw+3),z,fw,h,hand:i.even? ? 1 : -1,style:style) }
    end
    def drawers(count,x:@t,w:@w-2*@t,z:@z+3,height:@h-6,internal:false,gola:false)
      gola ||= @gola && !internal
      height=@h-@gola_gap-3 if gola
      gap=gola ? @gola_gap : 3.0; available=height-(count-1)*gap
      raise ArgumentError,'Drawer opening too small' if available/count<110
      front_h=available/count
      count.times do |i|
        zz=z+i*(front_h+gap); fw=internal ? w-30 : w+2*@t-3; fx=internal ? x+15 : x-@t+1.5
        m=front(fx,zz,fw,front_h,name:"Drawer #{i+1}",kind:'drawer',y:internal ? -@d+24 : -@d)
        @data[:motions].find { |q| q[:id]==m }[:requires_clear_front]=true if internal
        bw=w-25.0; bx=x+12.5; len=([250,300,350,400,450,500,550].select { |v| v<=@d-65 }.max || 200).to_f
        bh=[front_h-45,180].min; by=-@d+28; bz=zz+18
        panel('Drawer left',len,bh,15,[bx,by,bz],Y,Z,X,material:'Drawer',motion:m)
        panel('Drawer right',len,bh,15,[bx+bw-15,by,bz],Y,Z,X,material:'Drawer',motion:m)
        panel('Drawer back',bw-30,bh,15,[bx+15,by+len,bz],X,Z,NY,material:'Drawer',motion:m)
        panel('Drawer inner front',bw-30,bh,15,[bx+15,by+15,bz],X,Z,NY,material:'Drawer',motion:m)
        panel('Drawer bottom',bw-30,len-30,9,[bx+15,by+15,bz],material:'Drawer',motion:m)
        [x,x+w-12.5].each { |rx| hw('Drawer runner',[rx,by,bz],size:[12.5,len,35],recipe:'side-runner-12.5') }
      end
    end
    def angled_carcass
      raise ArgumentError,'Corner wings need at least 350 mm of usable return' if @w<900 || @d<900
      k=560.0
      outline=@recipe==:diagonal ? [[0,0],[@w,0],[@w,-k],[k,-@d],[0,-@d]] : [[0,0],[@w,0],[@w,-k],[k,-k],[k,-@d],[0,-@d]]
      @data[:footprint]=outline
      # Polygon floors and backs retain the actual corner shape in DXF.
      min_y=outline.map(&:last).min; poly=outline.map { |x,y| [x,y-min_y] }
      panel('Corner floor',@w,@d,18,[0,min_y,@z],outline:poly,material:'Carcass')
      panel('Corner top',@w,@d,18,[0,min_y,@z+@h-18],outline:poly,material:'Carcass')
      panel('Corner back X',@w,@h-36,18,[0,0,@z+18],X,Z,NY)
      panel('Corner back Y',@d-18,@h-36,18,[0,-@d,@z+18],Y,Z,X)
      panel('Corner end X',k,@h-36,18,[@w-18,-k,@z+18],Y,Z,X)
      panel('Corner end Y',k-18,@h-36,18,[18,-@d,@z+18],X,Z,NY)
      if @alu
        # Diagonal corner uses structural board decks inside a real extrusion
        # cage; this exception is explicit in the bill of materials.
        outline.each { |x,y| profile('Corner post',@h-36,[[x-25.4,0].max,y==0 ? -38.1 : y,@z+18],X,Y,Z) }
        @data[:warnings] << 'Corner decks are 18 mm structural board in aluminum modes.'
      end
      feet
      if @recipe==:diagonal
        dx=@w-k; dy=@d-k; len=Math.sqrt(dx*dx+dy*dy); angle=Math.atan2(dy,dx)*180/Math::PI
        before=parts.size; mh=@data[:motions].size
        front(0,@z+1.5,len-3,@h-3,hand:1,name:'Diagonal door')
        # Rotate the complete front recipe, including its hardware and hinge.
        generated=@data[:motions][mh..]; ids=generated.map { |m| m[:id] }
        shift=[k,-@d,0]
        parts[before..].each { |p| p[:o]=Math3.add(Math3.rotate(p[:o],angle),Math3.add(shift,Math3.rotate([0,@d,0],angle))); [:u,:v,:n].each { |a| p[a]=Math3.rotate(p[a],angle) } }
        hardware.select { |h| ids.include?(h[:motion]) }.each { |h| h[:o]=Math3.add(Math3.rotate(h[:o],angle),Math3.add(shift,Math3.rotate([0,@d,0],angle))); h[:axis]=Math3.rotate(h[:axis],angle) }
        generated.each { |m| m[:pivot]=Math3.add(Math3.rotate(m[:pivot],angle),Math3.add(shift,Math3.rotate([0,@d,0],angle))); m[:front]=nil }
      else
        front(k+2,@z+1.5,@w-k-4,@h-3,y:-k,hand:-1,name:'Corner front X',travel:90)
        # A perpendicular leaf on the second return, independently hinged.
        before=parts.size; hc=hardware.size; mc=@data[:motions].size
        front(0,@z+1.5,@d-k-4,@h-3,hand:1,name:'Corner front Y',travel:90,y:0)
        shift=[k,-@d+2,0]
        parts[before..].each { |p| p[:o]=Math3.add(Math3.rotate(p[:o],90),shift); [:u,:v,:n].each { |a| p[a]=Math3.rotate(p[a],90) } }
        hardware[hc..].each { |h| h[:o]=Math3.add(Math3.rotate(h[:o],90),shift); h[:axis]=Math3.rotate(h[:axis],90) }
        @data[:motions][mc..].each { |m| m[:pivot]=Math3.add(Math3.rotate(m[:pivot],90),shift); m[:front]=nil }
      end
    end
    def build
      carcass
      return if [:diagonal,:l_corner].include?(@recipe)
      case @recipe
      when :single then shelf(@z+@h/2); doors(count:1)
      when :double,:face_frame,:shaker
        shelf(@z+@h/2); doors(count:2,style:@recipe==:shaker ? 'shaker' : nil)
        if @recipe==:face_frame
          [0,@w-38].each { |x| panel('Face frame stile',38,@h,20,[x,-@d+20,@z],X,Z,NY,material:'Timber') }
          [@z,@z+@h-38].each { |z| panel('Face frame rail',@w-76,38,20,[38,-@d+20,z],X,Z,NY,material:'Timber') }
        end
      when :open then [1,2].each { |i| shelf(@z+@h*i/3.0) }
      when :drawers2,:drawers3,:drawers4 then drawers(@recipe.to_s[-1].to_i)
      when :gola
        drawers(2,gola:true)
      when :sink
        doors(count:2); hw('Sink bowl / appliance envelope',[@w/2-230,-@d+70,@z+@h-170],size:[460,390,170],recipe:'appliance-envelope')
        hw('Tap',[@w/2,-70,@z+@h],size:[25,280,25],kind:'cylinder',recipe:'appliance-envelope')
        @data[:warnings] << 'Sink and worktop cutout require the selected sink template.'
      when :oven
        shelf(@z+55,'Oven support'); appliance('Oven',@t,-@d+15,@z+85,@w-2*@t,@d-30,580)
        panel('Oven vent fascia',@w-3,65,18,[1.5,-@d,@z+@h-65],X,Z,NY,material:'Front')
        hw('Hob glass',[25,-@d+40,@z+@h+30],size:[@w-50,@d-100,6],recipe:'appliance-glass')
      when :dishwasher
        appliance('Dishwasher',25,-@d+10,@z+10,@w-50,@d-20,@h-25)
      when :pullout,:waste
        m=front(1.5,@z+1.5,@w-3,@h-(@gola ? @gola_gap+1.5 : 3),kind:'drawer',name:'Pullout',travel:@d-100)
        [@z+55,@z+@h*0.52].each do |z|
          shelf(z,'Pullout tray',x:@t+15,w:@w-2*@t-30,depth:@d-100,motion:m)
          [@t+15,@w-@t-25].each { |x| hw('Basket side',[x,-@d+40,z+15],size:[10,@d-120,100],motion:m,recipe:'basket-template') }
        end
        hw('Waste bin',[@t+35,-@d+80,@z+70],size:[@w-2*@t-70,@d-180,300],motion:m,recipe:'waste-bin-envelope') if @recipe==:waste
        hw('Pullout runner',[@w/2-20,-@d+30,@z+20],size:[40,@d-80,30],recipe:'pullout-runner-template')
      when :tray
        doors(count:1); 3.times { |i| panel('Tray divider',@d-80,@h-140,9,[@t+(@w-2*@t)*(i+1)/4,-@d+30,@z+30],Y,Z,X) }
      when :blind_left,:blind_right
        blind=@d+65; access=@w-blind
        raise ArgumentError,"Blind corner leaves only #{access} mm access; minimum 450" if access<450
        left=@recipe==:blind_left
        fh=@h-(@gola ? @gola_gap+1.5 : 3)
        panel('Fixed blind fascia',blind-3,fh,18,[left ? 1.5 : access+1.5,-@d,@z+1.5],X,Z,NY,material:'Front')
        # Hinge is away from the blind/return junction so the leaf clears it.
        if access-3>650 && @wall
          doors(x:left ? blind+1.5 : 1.5,w:access-3,z:@z+1.5,h:fh,count:2)
        else
          front(left ? blind+1.5 : 1.5,@z+1.5,access-3,fh,hand:left ? -1 : 1,name:'Blind access door')
        end
        shelf(@z+@h/2)
        @data[:blind]={side:left ? 'left' : 'right',width:blind,access:access,return_clearance:65}
      when :glass,:mirror
        [1,2].each { |i| shelf(@z+@h*i/3) }; doors(style:@recipe.to_s,count:2)
      when :lift then front(1.5,@z+1.5,@w-3,@h-3,kind:'lift',travel:85,name:'Lift flap')
      when :bifold
        fh=(@h-6)/2; top=front(1.5,@z+fh+4.5,@w-3,fh,kind:'lift',travel:65,name:'Upper bifold leaf')
        front(1.5,@z+1.5,@w-3,fh,kind:'fold',travel:130,name:'Lower bifold leaf',parent:top)
      when :hood
        shelf(@z+300,'Hood isolation shelf'); doors(z:@z+302,h:@h-304)
        hw('Extractor envelope',[75,-@d+20,@z],size:[@w-150,@d-40,240],recipe:'hood-envelope')
        @data[:warnings] << 'Hood appliance and hob clearance must use the selected manufacturer installation sheet.'
      when :wine
        3.times { |i| shelf(@z+(@h-36)*(i+1)/4,'Wine shelf') }
        2.times { |i| panel('Wine divider',@d-40,@h-50,12,[@w*(i+1)/3,-@d+20,@z+25],Y,Z,X) }
      when :plate
        shelf(@z+@h/2); (0...9).each { |i| hw('Plate divider rod',[45+i*(@w-90)/8,-@d+40,@z+45],size:[5,@h*0.38,5],kind:'cylinder',recipe:'plate-rack-rod') }
      when :pantry,:split,:robe_shelves,:shoes
        shelves=@recipe==:shoes ? 9 : 5
        shelves.times { |i| shelf(@z+(@h-60)*(i+1)/(shelves+1)) }
        if @recipe==:split
          doors(h:717); doors(z:@z+720,h:@h-723)
        else
          doors
        end
      when :appliance_tower
        doors(h:597); shelf(@z+600,'Oven shelf'); appliance('Oven',@t,-@d+15,@z+620,@w-2*@t,@d-30,580)
        shelf(@z+1220,'Microwave shelf'); appliance('Microwave',@t,-@d+15,@z+1240,@w-2*@t,@d-30,380)
        shelf(@z+1640,'Upper shelf'); doors(z:@z+1643,h:@h-1646)
      when :fridge
        appliance('Refrigerator',@t+15,-@d+25,@z+15,@w-2*@t-30,@d-60,1750)
        shelf(@z+1820,'Fridge upper shelf'); doors(z:@z+1823,h:@h-1826)
      when :space_tower
        doors; drawers(5,z:@z+70,height:@h-180,internal:true,x:@t+25,w:@w-2*@t-50)
      when :hanging,:double_hang,:robe_combo,:robe_open,:trousers
        split_bay=[:robe_combo,:robe_open].include?(@recipe)
        if split_bay
          panel('Wardrobe bay divider',@d-40,@h-36,18,[@w/2-9,-@d+18,@z+18],Y,Z,X)
          shelf(@z+@h-350,'Left loft shelf',x:18,w:@w/2-27)
          shelf(@z+@h-350,'Right loft shelf',x:@w/2+9,w:@w/2-27)
        else
          shelf(@z+@h-350,'Loft shelf')
        end
        rods=@recipe==:double_hang ? [@z+950,@z+@h-430] : [@z+@h-430]
        rods.each { |z| hw('Hanging rail',[split_bay ? @w/2+19 : @t+10,-@d/2,z],size:[25,split_bay ? @w/2-47 : @w-2*@t-20,25],kind:'cylinder',axis:X,recipe:'wardrobe-rail') }
        drawers(3,z:@z+40,height:650,internal:true,x:18,w:@w/2-27) if split_bay
        if @recipe==:trousers
          m=motion('Trouser rack','drawer',[@t,-@d+30,@z+900],travel:400)
          8.times { |i| hw('Trouser bar',[60+i*(@w-120)/7,-@d+40,@z+950],size:[12,@d-100,12],kind:'cylinder',axis:Y,motion:m,recipe:'trouser-rack-template') }
        end
        doors unless @recipe==:robe_open
      when :sliding2,:sliding3
        n=@recipe==:sliding2 ? 2 : 3
        (1...n).each { |i| panel('Wardrobe divider',@d-80,@h-50,18,[@w*i/n.to_f-9,-@d+70,@z+25],Y,Z,X) }
        n.times do |i|
          x=@w*i/n.to_f+@t; shelf(@z+@h-350,'Bay loft shelf',x:x,w:@w/n.to_f-2*@t)
          hw('Hanging rail',[x,-@d/2,@z+@h-430],size:[25,@w/n.to_f-2*@t,25],kind:'cylinder',axis:X,recipe:'wardrobe-rail')
        end
        [@z+10,@z+@h-25].each { |z| profile("#{n}-lane sliding track",@w,[0,-@d-(n==3 ? 55 : 30),z],Y,Z,X,section:n==3 ? 'track3' : 'track') }
        overlap=30.0; fw=(@w+(n-1)*overlap)/n
        n.times do |i|
          fx=i*(fw-overlap)+1.5; yy=-@d-i*25
          m=front(fx,@z+30,fw-3,@h-60,kind:'slide',hand:i==0 ? 1 : -1,travel:fw-overlap,style:'sash',y:yy,name:"Sliding leaf #{i+1}")
          [fx+65,fx+fw-65].each { |x| hw('Sliding door roller',[x,yy-5,@z+25],size:[24,8,24],kind:'cylinder',axis:Y,motion:m,recipe:'sliding-roller-template') }
        end
      when :island
        # Two full-depth usable bays, with an explicit central partition.
        panel('Island central spine',@w-2*@t,@h-60,18,[@t,-@d/2,@z+30],X,Z,NY)
        shelf(@z+@h/2,depth:@d/2-45); doors(count:2)
        pc=parts.size; hc=hardware.size; mc=@data[:motions].size
        doors(count:2)
        shift=[@w,-@d,0]
        parts[pc..].each { |p| p[:o]=Math3.add(Math3.rotate(p[:o],180),shift); [:u,:v,:n].each { |a| p[a]=Math3.rotate(p[a],180) } }
        hardware[hc..].each { |h| h[:o]=Math3.add(Math3.rotate(h[:o],180),shift); h[:axis]=Math3.rotate(h[:axis],180) }
        @data[:motions][mc..].each { |m| m[:pivot]=Math3.add(Math3.rotate(m[:pivot],180),shift); m[:front]=nil }
        # Remove carcass back because the rear bay has operational doors.
        parts.reject! { |p| ['Back','Back ACP infill'].include?(p[:name]) }
      when :seating
        shelf(@z+@h/2); doors(count:2)
        panel('Seating worktop',@w+40,@d+320,30,[-20,-@d-20,@z+@h],material:'Worktop')
      else raise "Missing construction recipe: #{@recipe}"
      end
      gola_profiles
    end
    def appliance(name,x,y,z,w,d,h)
      hw("#{name} envelope",[x,y,z],size:[w,d,h],recipe:'appliance-envelope')
      hw("#{name} glass",[x+20,y-4,z+80],size:[w-40,4,[h-150,50].max],recipe:'appliance-glass')
    end
    def validate!
      ids=parts.map { |p| p[:id] }
      raise 'Duplicate part identifiers' unless ids.uniq.size==ids.size
      parts.each do |p|
        raise "Empty contour: #{p[:name]}" unless p[:outline].size>=3 && Math3.area(p[:outline])>0.1
        raise "Non-orthogonal part frame: #{p[:name]}" unless Math3.dot(p[:u],p[:v]).abs<1e-6 && Math3.dot(p[:u],p[:n]).abs<1e-6 && Math3.dot(p[:v],p[:n]).abs<1e-6
        p[:operations].each do |o|
          next if o[:face]=='EDGE' || o[:kind]!='drill'
          raise "Drill exceeds panel depth: #{p[:name]}" if o[:depth]>p[:t] || o[:depth]<=0
          12.times do |i|
            a=i*Math::PI/6; q=[o[:x]+o[:diameter]/2*Math.cos(a),o[:y]+o[:diameter]/2*Math.sin(a)]
            raise "Drill outside part contour: #{p[:name]} #{o}" unless Math3.inside?(q,p[:outline])
          end
        end
      end
      @data[:warnings] << 'Hardware machining templates need SKU and workshop approval before production release.' if parts.any? { |p| !p[:operations].empty? }
      true
    end
  end

  def profile_section(section,mode='aluminum')
    case section
    when 'frame'
      a=25.4; b=mode=='aluminum_economy' ? 25.4 : 38.1; t=1.2
      [rectangle(a,b),[[[t,t],[a-t,t],[a-t,b-t],[t,b-t]]]]
    when 'sash'
      outer=[[21.2,0],[0,0],[0,10],[3.5,10],[3.5,8.5],[1.5,8.5],[1.5,1.5],[5,1.5],[5,45],[21.2,45]].map { |d,f| [f,d] }
      inner=[[6.5,1.5],[19.7,1.5],[19.7,43.5],[6.5,43.5]].map { |d,f| [f,d] }
      [outer,[inner]]
    when 'gola_l'
      p=[[0,0],[1.2,0],[1.2,44],[2,48],[5,51],[9,53],[27.2,53],[27.2,56.5],[8,56.5],[4,55],[1,52],[0,48]]
      [p.map { |y,z| [27.2-y,56.5-z] },[]]
    when 'gola_c'
      p=[[27.2,0],[27.2,3.5],[9,3.5],[5,5],[2,8],[1.2,12],[1.2,61],[2,65],[5,68],[9,69.5],[27.2,69.5],[27.2,73],[8,73],[4,71.5],[1,68.5],[0,64],[0,9],[1,4.5],[4,1.5],[8,0]]
      [p.map { |y,z| [27.2-y,z] },[]]
    when 'handle' then [[[0,0],[18,0],[18,18],[16.5,18],[16.5,1.5],[0,1.5]],[]]
    when 'track' then [[[0,0],[58,0],[58,16],[56,16],[56,2],[30,2],[30,16],[28,16],[28,2],[2,2],[2,16],[0,16]],[]]
    when 'track3' then [[[0,0],[83,0],[83,16],[81,16],[81,2],[55,2],[55,16],[53,16],[53,2],[30,2],[30,16],[28,16],[28,2],[2,2],[2,16],[0,16]],[]]
    else raise ArgumentError,"Unknown profile section #{section}"
    end
  end
end

module AJBoardScaffold
  class Job
    attr_reader :data
    def initialize(name)
      @data={schema:'cabinex.job/1',version:VERSION,id:SecureRandom.uuid,name:name,units:'mm',cabinets:[],fixtures:[],openings:[],runs:[],warnings:[],created_at:Time.now.to_s}
    end
    def add(type,**args)
      c=Cabinet.new(type,id:format('C%04d',@data[:cabinets].size+1),**args).data
      @data[:cabinets] << c; c
    end
    def fixture(name,w,d,h,pose,material:'Worktop',holes:[])
      @data[:fixtures] << {id:"F#{@data[:fixtures].size+1}",name:name,w:w,d:d,h:h,pose:pose,material:material,holes:holes}
    end
    def run_panel(name,w,h,t,pose,material:'Graphite',run:nil)
      id="F#{@data[:fixtures].size+1}"
      p={id:id,name:name,kind:'panel',w:w.to_f,h:h.to_f,t:t.to_f,o:[0,0,0],u:X,v:Z,n:NY,outline:AJBoardScaffold.rectangle(w,h),holes:[],material:material,operations:[],grain:material=='Front' && h>w ? 'v' : 'u',edge_band:nil}
      @data[:fixtures] << {id:id,name:name,pose:pose,material:material,part:p,run:run,manufacturing:true}
    end
    def run_profile(name,length,pose,section:,run:,sources:[])
      id="F#{@data[:fixtures].size+1}"; outer,holes=AJBoardScaffold.profile_section(section)
      p={id:id,name:name,kind:'profile',w:27.2,h:section=='gola_l' ? 56.5 : 73.0,t:length.to_f,o:[0,0,0],u:Y,v:Z,n:X,outline:outer,holes:holes,material:'Graphite',operations:[],grain:'none',section:section,cut_length:length.to_f,stock_length:6000.0,miter_start:0,miter_end:0}
      @data[:fixtures] << {id:id,name:name,pose:pose,material:'Graphite',part:p,run:run,sources:sources,manufacturing:true}
    end
    def validate!
      @data[:runs].each do |r|
        r[:units].each_cons(2) { |a,b| raise "Run overlap #{r[:id]}" if a[:x]+a[:w]>b[:x]+0.01 }
        r[:units].each { |u| raise "Unit outside run #{r[:id]}" if u[:x]<-0.01 || u[:x]+u[:w]>r[:length]+0.01 }
        audit=Planner.audit_run(r[:length],r[:units],allowed:r.fetch(:allowed,[]))
        raise "Unclosed run #{r[:id]}: #{audit[:gaps]}" unless audit[:ok]
      end
      cabs=@data[:cabinets]
      cabs.each_with_index do |a,i|
        next if a[:zone]=='catalogue'
        pa=footprint(a); za=a[:pose][2]+(a[:type].start_with?('wall_','top_') ? 0 : 100)
        cabs[(i+1)..].each do |b|
          next if b[:zone]=='catalogue' || a[:zone]!=b[:zone]
          zb=b[:pose][2]+(b[:type].start_with?('wall_','top_') ? 0 : 100)
          next unless za+a[:h]>zb+0.1 && zb+b[:h]>za+0.1
          raise "Cabinet footprints intersect: #{a[:id]} #{b[:id]}" if Math3.overlap?(pa,footprint(b))
        end
      end
      true
    end
    def footprint(c)
      (c[:footprint] || [[0,0],[c[:w],0],[c[:w],-c[:d]],[0,-c[:d]]]).map { |x,y| Math3.world([x,y,0],c[:pose])[0,2] }
    end
  end

  def make_showcase
    job=Job.new('Cabinex Master / catalogue and kitchen studio')
    # 1524 mm clear gap, measured after the largest model envelope, not centres.
    cell_x=2600+1524; cell_y=1500+1524; cols=6
    MODES.each_with_index do |mode,mi|
      catalogue.each_with_index do |row,i|
        x=(i%cols)*cell_x; y=-((i/cols)*cell_y+mi*27000)
        c=job.add(row[:id],mode:mode,pose:[x,y,0,0]); c[:zone]='catalogue'; c[:exhibit]="Catalogue #{mode}"; c[:label]="#{row[:id]} | #{mode} | #{c[:w].round} x #{c[:h].round} x #{c[:d].round}"
      end
    end
    MODES.each_with_index do |mode,mi|
      %w[I L U GALLEY H].each_with_index do |shape,si|
        append_kitchen(job,shape:shape,mode:mode,width:5400,depth:4800,origin:[32000+si*9500,-mi*11000,0],name:"#{shape} / #{mode}",openings:[{wall:'A',kind:'window',x:1900,width:1600,sill:1050,height:950,clearance:25}])
      end
    end
    %w[board hybrid].each_with_index do |mode,mi|
      %w[I L U GALLEY H].each_with_index do |shape,si|
        append_kitchen(job,shape:shape,mode:mode,width:5400,depth:4800,origin:[85000+si*9500,-mi*11000,0],front_system:'gola',finger_gap:25,openings:[{wall:'A',kind:'window',x:1900,width:1600,sill:1050,height:950,clearance:25}])
      end
    end
    job.validate!; job
  end

  def append_kitchen(job,shape:,mode:,width:,depth:,origin:[0,0,0],name:nil,openings:[],front_system:'handled',finger_gap:25)
    fixture_start=job.data[:fixtures].size
    shape=shape.to_s.upcase; name ||= "#{shape} / #{mode}#{front_system=='gola' ? ' / Gola' : ''}"
    raise ArgumentError,'Supported layouts: I, L, U, GALLEY, H' unless %w[I L U GALLEY H].include?(shape)
    raise ArgumentError,'Unknown front system' unless %w[handled gola].include?(front_system)
    raise ArgumentError,'Room too small for the selected layout' if width<1800 || depth<1800
    raise ArgumentError,'Facing runs require at least 1200 mm between 600 mm counters' if %w[U GALLEY H].include?(shape) && (shape=='H' ? width : depth)<2400
    openings.each do |o|
      raise ArgumentError,'Unknown opening wall or kind' unless %w[A B C D].include?(o[:wall]) && %w[door window].include?(o[:kind])
      len=%w[A D].include?(o[:wall]) ? width : depth
      raise ArgumentError,'Opening outside room wall' unless o[:x]>=0 && o[:width]>0 && o[:x]+o[:width]<=len && o[:sill]>=0 && o[:height]>0
    end
    walls={ 'A'=>{o:[0,0,0],angle:0,length:width}, 'B'=>{o:[width,0,0],angle:-90,length:depth}, 'C'=>{o:[0,-depth,0],angle:90,length:depth}, 'D'=>{o:[width,-depth,0],angle:180,length:width} }
    selected=case shape; when 'I' then %w[A]; when 'L' then %w[A B]; when 'U' then %w[A B C]; when 'GALLEY' then %w[A D]; when 'H' then %w[B C]; end
    reservations=Hash.new { |h,k| h[k]=[] }; corner_units=Hash.new { |h,k| h[k]=[] }; joins=Hash.new { |h,k| h[k]=[] }
    upper_res=Hash.new { |h,k| h[k]=[] }; upper_corners=Hash.new { |h,k| h[k]=[] }; upper_joins=Hash.new { |h,k| h[k]=[] }
    span_at=proc { |wall,edge,take| edge==:start ? [0,take] : [walls[wall][:length]-take,walls[wall][:length]] }
    corners=[]
    corners << ['A','B',:end,:start] if %w[L U].include?(shape)
    corners << ['A','C',:start,:end] if shape=='U'
    corners.each do |a,b,enda,endb|
      free_a=walls[a][:length]-reservations[a].sum { |l,r| r-l }
      free_b=walls[b][:length]-reservations[b].sum { |l,r| r-l }
      candidate=Planner.choose_corner(free_a,free_b,depth:560,access:475,clearance:65)
      owner=candidate[:owner]=='A' ? a : b
      [[a,enda],[b,endb]].each do |wall,edge|
        owned=wall==owner; take=owned ? 1100 : 625
        reservations[wall] << span_at.call(wall,edge,take)
        joins[wall] << {edge:edge,owner:owned}
        corner_units[wall] << {x:span_at.call(wall,edge,take)[0],w:1100.0,type:edge==:start ? 'blind_left' : 'blind_right',corner:true} if owned
      end
      # Upper corners have their own 330 mm depth and 455 mm usable opening.
      # Try both owners if a window conflicts with the preferred upper corner.
      upper_owner=[owner,owner==a ? b : a].find do |candidate_owner|
        [[a,enda],[b,endb]].all? do |wall,edge|
          span=span_at.call(wall,edge,wall==candidate_owner ? 850 : 395)
          blocked=Planner.opening_intervals(openings,wall,1450,2170)+upper_res[wall]
          Planner.subtract(span,blocked)==[span]
        end
      end
      raise ArgumentError,'A door/window prevents both upper corner orientations; specify an intentional open corner.' unless upper_owner
      [[a,enda],[b,endb]].each do |wall,edge|
        owned=wall==upper_owner; take=owned ? 850 : 395
        upper_res[wall] << span_at.call(wall,edge,take)
        upper_joins[wall] << {edge:edge,owner:owned}
        upper_corners[wall] << {x:span_at.call(wall,edge,take)[0],w:850.0,type:edge==:start ? 'wall_blind_left' : 'wall_blind_right',corner:true} if owned
      end
    end
    selected.each { |wall| reservations[wall] << [depth/2-345,depth/2+345] } if shape=='H'
    zone="Kitchen #{name}"
    options={defer_run_parts:true,front_system:front_system,finger_gap:finger_gap}
    selected.each do |wall_id|
      wall=walls[wall_id]; length=wall[:length]
      at=proc { |x,y,z| [*Math3.add(origin,Math3.add(wall[:o],Math3.rotate([x,y,z],wall[:angle]))),wall[:angle]] }
      blocked=reservations[wall_id]+Planner.opening_intervals(openings,wall_id,100,850)
      units=corner_units[wall_id].dup
      Planner.subtract([50,length-50],blocked).each do |span|
        len=span[1]-span[0]; anchors=[]
        if wall_id=='A' && len>=2000
          window=openings.find { |o| o[:wall]=='A' && o[:kind]=='window' && o[:x]+o[:width]/2>=span[0]+450 && o[:x]+o[:width]/2<=span[1]-450 }
          sink_x=window ? window[:x]+window[:width]/2.0-450 : (span.sum-900)/2.0
          anchors << {x:sink_x,w:900,type:'base_sink'}
        end
        oven={x:span[0]+500,w:600,type:'base_oven'}; fridge={x:span[1]-900,w:900,type:'tall_fridge'}
        attempts=wall_id=='A' && len>=3500 ? [anchors+[oven,fridge],anchors+[oven],anchors+[fridge],anchors,[]] : wall_id!='A' && len>=2400 ? [[fridge],[]] : [anchors,[]]
        attempts=wall_id=='B' ? [[fridge],[]] : [[{x:span[0]+450,w:600,type:'base_oven'}],[]] if shape=='H' && span[0]<depth/2 && len>=1900
        solution=nil
        attempts.each do |locked|
          begin; solution=Planner.fill(span,anchors:locked); break; rescue ArgumentError; end
        end
        raise ArgumentError,'No useful cabinet arrangement fits the remaining wall span.' unless solution
        units.concat(solution)
      end
      # Cover deliberate 50 mm wall scribes; a blind return has a 65 mm face
      # closure between the perpendicular carcass and its first cabinet.
      [[0,50],[length-50,length]].each do |span|
        Planner.subtract(span,blocked).each { |l,r| units << {x:l,w:r-l,type:'filler',purpose:'wall scribe'} }
      end
      joins[wall_id].reject { |j| j[:owner] }.each do |j|
        x=j[:edge]==:start ? 560 : length-625
        units << {x:x,w:65,type:'filler',purpose:'corner opening clearance'}
      end
      if shape=='H'
        [depth/2-345,depth/2+280].each { |x| units << {x:x,w:65,type:'filler',purpose:'centre junction clearance'} }
      end
      allowed=Planner.opening_intervals(openings,wall_id,100,850).map { |s| {span:s,reason:'door/window height band and clearance'} }
      joins[wall_id].reject { |j| j[:owner] }.each { |j| allowed << {span:span_at.call(wall_id,j[:edge],560),reason:'perpendicular corner cabinet'} }
      allowed << {span:[depth/2-280,depth/2+280],reason:'H centre cabinet junction'} if shape=='H'
      units,audit=Planner.close_run(length,units,allowed:allowed)
      units.each_with_index { |u,i| u[:type]=front_system=='gola' ? 'base_gola' : 'base_drawers_3' if u[:type]=='base_single' && (front_system=='gola' ? [1,2].include?(i%4) : i%3==1) }
      units.select { |u| u[:type]=='filler' }.each do |u|
        tall_neighbour=units.find { |t| t[:type].start_with?('tall_') && ((t[:x]+t[:w]-u[:x]).abs<0.01 || (u[:x]+u[:w]-t[:x]).abs<0.01) }
        u.merge!(enclosure_height:2100,depth:650) if tall_neighbour
      end
      run={id:"#{zone} #{wall_id}",wall:wall_id,length:length,units:deep(units),origin:origin,angle:wall[:angle],allowed:allowed,audit:audit,front_system:front_system}
      job.data[:runs] << run
      bases=[]
      units.each do |u|
        if u[:type]=='filler'
          height=u[:enclosure_height] || 720-(front_system=='gola' ? finger_gap : 0)
          job.run_panel('Installation filler / '+u[:purpose],u[:w],height,18,at.call(u[:x],-u.fetch(:depth,560),100),material:'Front',run:run[:id]); next
        end
        c=job.add(u[:type],mode:mode,w:u[:w],pose:at.call(u[:x],0,0),options:options)
        c.merge!(zone:zone,exhibit:zone,run:run[:id],front_span:[u[:x],u[:x]+u[:w]]); bases << c
      end
      tall=merge_spans(units.select { |u| u[:type].start_with?('tall_') || u[:enclosure_height] }.map { |u| [u[:x],u[:x]+u[:w]] })
      # Plinth faces continue beneath modules and fillers. At corners the
      # owner and return meet with a butt joint, without overlapping boards.
      plinth_limits=[0.0,length.to_f]
      joins[wall_id].each { |j| take=j[:owner] ? 505 : 521; j[:edge]==:start ? plinth_limits[0]=take : plinth_limits[1]=length-take }
      plinth_blocked=Planner.opening_intervals(openings,wall_id,0,100)
      Planner.subtract(plinth_limits,plinth_blocked).each do |l,r|
        # Tall fridge carcasses use a deeper plinth with deliberate returns.
        boundaries=([l,r]+tall.flatten.select { |x| x>l && x<r }).uniq.sort
        boundaries.each_cons(2) do |a,b|
          deeper=tall.any? { |x,y| a>=x && b<=y }; y=deeper ? -595 : -505
          each_stock_span(a,b,2400) { |x,z| job.run_panel('Continuous run plinth',z-x,95,16,at.call(x,y,0),run:run[:id]) }
        end
        tall.flatten.select { |x| x>l && x<r }.each do |x|
          pose=at.call(x,-595,0); pose[3]+=90
          job.run_panel('Plinth depth return',90,95,16,pose,run:run[:id])
        end
      end
      build_run_gola(job,bases,units,run,at,joins[wall_id]) if front_system=='gola'
      # Tops reach the perpendicular worktop (590 mm), instead of stopping
      # at the cabinet's larger 625 mm opening-clearance reservation.
      top_blocked=Planner.opening_intervals(openings,wall_id,820,860)+tall
      joins[wall_id].reject { |j| j[:owner] }.each { |j| top_blocked << span_at.call(wall_id,j[:edge],590) }
      top_blocked << [depth/2-310,depth/2+310] if shape=='H'
      Planner.subtract([0,length],top_blocked).each do |l,r|
        add_run_worktop(job,l,r,units,at,590,run[:id])
      end
      upper_openings=Planner.opening_intervals(openings,wall_id,1450,2170)+tall
      upper_spans=Planner.subtract([50,length-50],upper_openings+upper_res[wall_id])
      # A tall unit can leave a short fragment beside the shallower upper
      # corner. Enlarge that corner's accessible bay and divide its leaves.
      upper_spans=upper_spans.reject do |l,r|
        next false unless r-l<300
        corner=upper_corners[wall_id].find { |c| (c[:x]-r).abs<0.01 || (c[:x]+c[:w]-l).abs<0.01 }
        next false unless corner
        corner[:x]=l if (corner[:x]-r).abs<0.01
        corner[:w]+=r-l; corner[:closure_adjustment]=r-l; true
      end
      uppers=upper_corners[wall_id].dup+Planner.upper_plan(upper_spans,units)
      [[0,50],[length-50,length]].each do |span|
        Planner.subtract(span,upper_openings+upper_res[wall_id]).each { |l,r| uppers << {x:l,w:r-l,type:'filler',purpose:'upper wall scribe'} }
      end
      upper_allowed=upper_openings.map { |s| {span:s,reason:'upper door/window band or tall cabinet'} }
      upper_joins[wall_id].reject { |j| j[:owner] }.each do |j|
        x=j[:edge]==:start ? 330 : length-395
        uppers << {x:x,w:65,type:'filler',purpose:'upper corner opening clearance'}
        upper_allowed << {span:span_at.call(wall_id,j[:edge],330),reason:'perpendicular upper corner cabinet'}
      end
      uppers,upper_audit=Planner.close_run(length,uppers,allowed:upper_allowed,upper:true)
      upper_run=run.merge(id:run[:id]+' / upper',units:deep(uppers),allowed:upper_allowed,audit:upper_audit,level:'upper')
      job.data[:runs] << upper_run
      uppers.each do |u|
        if u[:type]=='filler'
          job.run_panel('Upper filler / '+u[:purpose],u[:w],720,18,at.call(u[:x],-330,1450),material:'Front',run:upper_run[:id]); next
        end
        c=job.add(u[:type],mode:mode,w:u[:w],pose:at.call(u[:x],0,1450))
        c.merge!(zone:zone,exhibit:zone,run:upper_run[:id],front_span:[u[:x],u[:x]+u[:w]],aligns_to:u[:base_boundary])
      end
    end
    if shape=='H'
      at=proc { |x,y,z| [origin[0]+x,origin[1]-depth/2+280+y,origin[2]+z,0] }
      units=Planner.fill([625,width-625],anchors:[{x:width/2.0-450,w:900,type:'base_sink'}])
      units.each_with_index { |u,i| u[:type]=front_system=='gola' ? 'base_gola' : 'base_drawers_3' if u[:type]=='base_single' && i.even? }
      units=[{x:560,w:65,type:'filler',purpose:'centre end clearance'}]+units+[{x:width-625,w:65,type:'filler',purpose:'centre end clearance'}]
      allowed=[{span:[0,560],reason:'left side run'},{span:[width-560,width],reason:'right side run'}]
      units,audit=Planner.close_run(width,units,allowed:allowed)
      run={id:zone+' H centre',wall:'CENTRE',length:width,units:units,allowed:allowed,audit:audit,front_system:front_system}; job.data[:runs] << run
      bases=[]
      units.each do |u|
        if u[:type]=='filler'
          job.run_panel('H centre filler',u[:w],720-(front_system=='gola' ? finger_gap : 0),18,at.call(u[:x],-560,100),material:'Front',run:run[:id]); next
        end
        c=job.add(u[:type],mode:mode,w:u[:w],pose:at.call(u[:x],0,0),options:options)
        c.merge!(zone:zone,exhibit:zone,run:run[:id],front_span:[u[:x],u[:x]+u[:w]]); bases << c
      end
      each_stock_span(521,width-521,2400) { |l,r| job.run_panel('Continuous H centre plinth',r-l,95,16,at.call(l,-505,0),run:run[:id]) }
      build_run_gola(job,bases,units,run,at,[]) if front_system=='gola'
      add_run_worktop(job,590,width-590,units,at,620,run[:id])
    end
    selected.each do |wall_id|
      wall=walls[wall_id]; wall_openings=openings.select { |o| o[:wall]==wall_id }
      xs=([0,wall[:length]]+wall_openings.flat_map { |o| [o[:x],o[:x]+o[:width]] }).uniq.sort
      xs.each_cons(2) do |l,r|
        mid=(l+r)/2; opening=wall_openings.find { |o| mid>=o[:x] && mid<=o[:x]+o[:width] }
        vertical=opening ? [[0,opening[:sill]],[opening[:sill]+opening[:height],2600]] : [[0,2600]]
        vertical.each do |z0,z1|
          next if z1<=z0
          pos=Math3.add(origin,Math3.add(wall[:o],Math3.rotate([l,0,z0],wall[:angle])))
          job.fixture('Room wall',r-l,100,z1-z0,[*pos,wall[:angle]],material:'Wall')
        end
      end
      wall_openings.each do |o|
        pos=Math3.add(origin,Math3.add(wall[:o],Math3.rotate([o[:x],45,o[:sill]],wall[:angle])))
        job.fixture('Window glazing',o[:width],4,o[:height],[*pos,wall[:angle]],material:'Glass') if o[:kind]=='window'
        job.data[:openings] << o.merge(zone:zone)
      end
    end
    job.fixture("#{name} / room floor",width+200,depth+200,25,[origin[0]-100,origin[1]-depth-100,origin[2]-25,0],material:'Floor')
    job.data[:fixtures][fixture_start..].each { |f| f[:zone]=zone }
    job.data[:warnings] << "#{name}: appliance envelopes and access clearances require project-specific review."
    job
  end

  def each_stock_span(l,r,maximum)
    count=((r-l)/maximum.to_f).ceil
    count.times { |i| yield(l+(r-l)*i/count,l+(r-l)*(i+1)/count) } if count>0
  end

  def add_run_worktop(job,l,r,units,at,depth,run_id)
    cursor=l
    while cursor<r-0.01
      candidates=units.map { |u| u[:x]+u[:w] }.select { |v| v>cursor && v<=cursor+2400 }
      finish=r-cursor<=2400 ? r : (candidates.max || cursor+2400)
      crossing=units.find { |u| u[:type]=='base_sink' && u[:x]<finish && u[:x]+u[:w]>finish }
      finish=crossing[:x] if crossing
      raise ArgumentError,'Cannot place a worktop stock seam clear of the sink' if finish<=cursor
      cutouts=units.select { |u| u[:type]=='base_sink' && u[:x]>=cursor && u[:x]+u[:w]<=finish }.map do |u|
        sx=u[:x]+u[:w]/2.0-cursor-230; [[sx,80],[sx+460,80],[sx+460,470],[sx,470]]
      end
      job.fixture('Continuous worktop',finish-cursor,depth,30,at.call(cursor,-590,820),holes:cutouts)
      job.data[:fixtures].last.merge!(run:run_id,manufacturing:true)
      cursor=finish
    end
  end

  def build_run_gola(job,bases,units,run,at,joins)
    specs=[]
    bases.select { |c| c[:gola] }.each do |c|
      l,r=c[:front_span]
      specs << {section:'gola_l',z:c[:gola][:top_z]-56.5,l:l,r:r,source:c[:id]}
      c[:gola][:centres].each { |z| specs << {section:'gola_c',z:z-36.5,l:l,r:r,source:c[:id]} }
    end
    # L rails continue over deliberate fillers; C rails bridge a filler only
    # when there are drawers at the same elevation on both sides.
    specs.group_by { |s| [s[:section],s[:z].round(5)] }.each do |(section,z),group|
      intervals=group.map { |s| [s[:l],s[:r]] }
      units.select { |u| u[:type]=='filler' && !u[:enclosure_height] }.each do |u|
        left=group.any? { |s| (s[:r]-u[:x]).abs<0.01 }; right=group.any? { |s| (s[:l]-u[:x]-u[:w]).abs<0.01 }
        intervals << [u[:x],u[:x]+u[:w]] if section=='gola_l' ? left || right : left && right
      end
      merge_spans(intervals).each do |l,r|
        start_miter=0; end_miter=0
        if section=='gola_l'
          joins.each do |join|
            edge=join[:edge]; length=run[:length]
            if edge==:start && l<=625
              l=532.8; start_miter=-45
            elsif edge==:end && r>=length-625
              r=length-532.8; end_miter=-45
            end
          end
        end
        sources=group.select { |s| s[:l]<r && s[:r]>l }.map { |s| s[:source] }
        each_stock_span(l,r,5975) do |a,b|
          job.run_profile("Continuous #{section=='gola_l' ? 'L' : 'C'} Gola",b-a,at.call(a,-560,z),section:section,run:run[:id],sources:sources)
          part=job.data[:fixtures].last[:part]; part[:miter_start]=start_miter if (a-l).abs<0.01; part[:miter_end]=end_miter if (b-r).abs<0.01
        end
      end
    end
  end

  def merge_spans(spans)
    out=[]; spans.sort.each { |a,b| out.empty? || a>out[-1][1]+0.01 ? out << [a,b] : out[-1][1]=[b,out[-1][1]].max }; out
  end
  def run_gap_report(data,placements:nil)
    rows=data[:runs].map do |r|
      units=deep(r[:units]); alignment=[]
      if placements
        cabinets=data[:cabinets].select { |c| c[:run]==r[:id] }
        cabinets.each do |c|
          actual=placements[c[:id]]
          unless actual
            units.reject! { |u| (u[:x]-c[:front_span][0]).abs<0.01 && u[:type]==c[:type] }
            alignment << {cabinet:c[:id],error:'Cabinet is missing from the model'}; next
          end
          delta=Math3.rotate(Math3.add(actual[:pose][0,3],Math3.scale(c[:pose][0,3],-1)),-c[:pose][3])
          u=units.find { |q| (q[:x]-c[:front_span][0]).abs<0.01 && q[:type]==c[:type] }
          u.merge!(x:u[:x]+delta[0],w:actual[:width]) if u
          if delta[1].abs>0.1 || delta[2].abs>0.1 || (actual[:pose][3]-c[:pose][3]).abs>0.01
            alignment << {cabinet:c[:id],cross_run_offset:delta[1],height_offset:delta[2],angle:actual[:pose][3]}
          end
        end
      end
      audit=Planner.audit_run(r[:length],units,allowed:r.fetch(:allowed,[]))
      audit.merge(run:r[:id],alignment_errors:alignment,redivision_attempts:r.dig(:audit,:redivision_attempts) || 0,allowed:r[:allowed])
    end
    {job_id:data[:id],source:placements ? 'current SketchUp cabinet placements' : 'planned cabinet placements',run_count:rows.size,unexplained_gaps:rows.sum { |r| r[:gaps].size },overlaps:rows.sum { |r| r[:overlaps].size },alignment_errors:rows.sum { |r| r[:alignment_errors].size },runs:rows}
  end
  def check_runs!
    a=active_adapter; placements={}
    a.cabinet_entities.select(&:valid?).each do |e|
      c=JSON.parse(e.get_attribute(DICT,'cabinet'),symbolize_names:true); t=e.transformation
      placements[c[:id]]={pose:[*t.origin.to_a.map { |v| v.to_f*25.4 },Math.atan2(t.xaxis.y,t.xaxis.x)*180/Math::PI],width:c[:w]*t.xaxis.length}
    end
    report=run_gap_report(a.job,placements:placements)
    write_json(File.join(HOME,'output','run_gap_report.json'),report)
    "#{report[:run_count]} model runs checked: #{report[:unexplained_gaps]} unexplained gaps, #{report[:overlaps]} overlaps, #{report[:alignment_errors]} alignment errors."
  end

  module Export
    extend self
    def all_parts(data)
      parts=data[:cabinets].flat_map { |c| c[:parts].map { |p| p.merge(cabinet:c[:id],mode:c[:mode],type:c[:type]) } }
      data.fetch(:fixtures,[]).select { |f| f[:manufacturing] || %w[Worktop Front].include?(f[:material]) }.each do |f|
        if f[:part]
          parts << f[:part].merge(cabinet:'RUN',mode:'shared',type:f[:name],run:f[:run]); next
        end
        parts << {id:f[:id],cabinet:'RUN',type:f[:name],mode:'shared',name:f[:name],kind:'panel',material:f[:material],w:f[:w].to_f,h:f[:d].to_f,t:f[:h].to_f,o:f[:pose][0,3],u:X,v:Y,n:Z,outline:AJBoardScaffold.rectangle(f[:w],f[:d]),holes:f[:holes] || [],operations:[],grain:'u',edge_band:nil}
      end
      parts
    end
    def bars(parts,kerf:3,trim:10)
      stocks=[]; rejected=[]
      parts.select { |p| p[:kind]=='profile' }.group_by { |p| [p[:section],p[:stock_length]] }.each do |key,ps|
        ps.sort_by { |p| -p[:cut_length] }.each do |p|
          length=p[:cut_length]
          if length+kerf>key[1]-2*trim
            rejected << {part:p[:id],reason:'Profile exceeds stock length'}; next
          end
          b=stocks.select { |s| s[:key]==key && s[:remaining]>=length+kerf }.min_by { |s| s[:remaining] }
          unless b
            b={key:key,remaining:key[1]-2*trim,cuts:[]}; stocks << b
          end
          b[:cuts] << {part:p[:id],length:length,start_miter:p[:miter_start],end_miter:p[:miter_end],offset:key[1]-trim-b[:remaining]}; b[:remaining]-=length+kerf
        end
      end
      {stocks:stocks,rejected:rejected}
    end
    def pair(io,code,value); io << "#{code}\n#{value}\n"; end
    def poly(io,points,layer)
      pair(io,0,'LWPOLYLINE'); pair(io,100,'AcDbEntity'); pair(io,8,layer); pair(io,100,'AcDbPolyline'); pair(io,90,points.size); pair(io,70,1)
      points.each { |x,y| pair(io,10,x.round(4)); pair(io,20,y.round(4)) }
    end
    def circle(io,x,y,r,layer)
      pair(io,0,'CIRCLE'); pair(io,100,'AcDbEntity'); pair(io,8,layer); pair(io,100,'AcDbCircle'); pair(io,10,x.round(4)); pair(io,20,y.round(4)); pair(io,30,0); pair(io,40,r.round(4))
    end
    def label(io,x,y,text,height=12)
      pair(io,0,'TEXT'); pair(io,100,'AcDbEntity'); pair(io,8,'PART_ID'); pair(io,100,'AcDbText'); pair(io,10,x); pair(io,20,y); pair(io,30,0); pair(io,40,height); pair(io,1,text)
    end
    def dxf(path)
      body=StringIO.new; yield body
      layers=['0','PART_ID']
      body.string.lines.map(&:strip).each_slice(2) { |code,value| layers << value if code=='8' }
      layers.uniq!
      File.open(path,'w') do |io|
        pair(io,0,'SECTION'); pair(io,2,'HEADER'); pair(io,9,'$ACADVER'); pair(io,1,'AC1015'); pair(io,9,'$INSUNITS'); pair(io,70,4); pair(io,9,'$MEASUREMENT'); pair(io,70,1); pair(io,0,'ENDSEC')
        pair(io,0,'SECTION'); pair(io,2,'TABLES')
        pair(io,0,'TABLE'); pair(io,2,'LTYPE'); pair(io,70,1)
        pair(io,0,'LTYPE'); pair(io,100,'AcDbSymbolTableRecord'); pair(io,100,'AcDbLinetypeTableRecord'); pair(io,2,'CONTINUOUS'); pair(io,70,0); pair(io,3,'Solid line'); pair(io,72,65); pair(io,73,0); pair(io,40,0.0); pair(io,0,'ENDTAB')
        pair(io,0,'TABLE'); pair(io,2,'LAYER'); pair(io,70,layers.size)
        layers.each_with_index do |layer,i|
          pair(io,0,'LAYER'); pair(io,100,'AcDbSymbolTableRecord'); pair(io,100,'AcDbLayerTableRecord'); pair(io,2,layer); pair(io,70,0); pair(io,62,layer.start_with?('CUT') ? 7 : (i%6)+1); pair(io,6,'CONTINUOUS')
        end
        pair(io,0,'ENDTAB'); pair(io,0,'ENDSEC')
        pair(io,0,'SECTION'); pair(io,2,'ENTITIES'); io << body.string; pair(io,0,'ENDSEC'); pair(io,0,'EOF')
      end
    end
    def layer(o)
      "#{o[:face]}_#{o[:tool]}_D#{o[:diameter].to_s.tr('.','p')}_Z#{o[:depth].to_s.tr('.','p')}"
    end
    def part_dxf(p,path)
      dxf(path) do |io|
        poly(io,p[:outline],'CUT_OUTER'); p[:holes].each { |h| poly(io,h,'CUT_INNER') }
        p[:operations].each do |o|
          next if o[:face]=='EDGE' || o[:kind]!='drill'
          circle(io,o[:x],o[:y],o[:diameter]/2.0,layer(o))
        end
        label(io,10,-25,p[:id]+' '+p[:name])
      end
      p[:operations].select { |o| o[:face]=='EDGE' }.group_by { |o| o[:edge] }.each do |edge,ops|
        dxf(path.sub(/\.dxf\z/,"_EDGE_#{edge}.dxf")) do |io|
          poly(io,AJBoardScaffold.rectangle(p[:h],p[:t]),'EDGE_OUTLINE')
          ops.each { |o| circle(io,o[:y],p[:t]/2.0,o[:diameter]/2.0,layer(o)) }
          label(io,5,-20,"#{p[:id]} EDGE #{edge}; X=panel V, Y=thickness")
        end
      end
    end
    def sheets(parts,stock_w:2440,stock_h:1220,kerf:4,margin:10)
      bins=[]; rejects=[]
      parts.select { |p| p[:kind]=='panel' }.group_by { |p| [p[:material],p[:t]] }.each do |key,group|
        group.sort_by { |p| -p[:w]*p[:h] }.each do |p|
          # Stock grain is +X (the 2440 mm direction). Keep every panel's
          # declared grain axis consistent, rather than rotating only outliers.
          orientations=case p[:grain]
                       when 'v' then [[p[:h],p[:w],true]]
                       when 'u' then [[p[:w],p[:h],false]]
                       else [[p[:w],p[:h],false],[p[:h],p[:w],true]]
                       end
          options=orientations.select { |w,h,_| w<=stock_w-2*margin && h<=stock_h-2*margin }
          # Grain can run along the sheet's long axis; the canonical panel v
          # axis is length. Rotate the whole stock convention consistently.
          if options.empty?
            rejects << {id:p[:id],reason:'Part exceeds selected sheet size',w:p[:w],h:p[:h],material:p[:material]}; next
          end
          choice=nil
          bins.each do |b|
            next unless b[:key]==key
            b[:free].each_with_index do |rect,idx|
              options.each do |w,h,rot|
                next unless w<=rect[2] && h<=rect[3]
                score=rect[2]*rect[3]-w*h
                choice=[score,b,idx,w,h,rot] if choice.nil? || score<choice[0]
              end
            end
          end
          unless choice
            b={key:key,free:[[margin,margin,stock_w-2*margin,stock_h-2*margin]],placements:[],width:stock_w,height:stock_h}; bins << b
            w,h,rot=options.first; choice=[0,b,0,w,h,rot]
          end
          _,b,idx,w,h,rot=choice; x,y,rw,rh=b[:free].delete_at(idx)
          b[:placements] << {part:p,x:x,y:y,w:w,h:h,rotated:rot}
          b[:free] << [x+w+kerf,y,rw-w-kerf,h] if rw-w>kerf
          b[:free] << [x,y+h+kerf,rw,rh-h-kerf] if rh-h>kerf
        end
      end
      {sheets:bins,rejected:rejects}
    end
    def transform_uv(x,y,placement)
      placement[:rotated] ? [placement[:x]+y,placement[:y]+placement[:part][:w]-x] : [placement[:x]+x,placement[:y]+y]
    end
    def package(job,directory,release:false)
      raise 'Machine release is disabled in this development edition. Approve hardware, stock and the machine postprocessor first.' if release
      raise 'Choose an empty export folder to avoid mixing parts from different revisions.' if Dir.exist?(directory) && !Dir.empty?(directory)
      data=job.respond_to?(:data) ? job.data : job
      parts=all_parts(data)
      operations=parts.flat_map { |p| p[:operations].map { |o| o.merge(part:p[:id],cabinet:p[:cabinet],part_thickness:p[:t]) } }
      raise 'Production release withheld: select and approve hardware recipes first' if release && operations.any? { |o| o[:status]!='approved' }
      FileUtils.mkdir_p(directory); pd=File.join(directory,'parts_dxf'); FileUtils.mkdir_p(pd)
      AJBoardScaffold.write_json(File.join(directory,'job.json'),data)
      AJBoardScaffold.write_json(File.join(directory,'machining.json'),operations)
      CSV.open(File.join(directory,'parts.csv'),'w') do |csv|
        csv << %w[part_id cabinet family mode name kind material width_mm height_mm thickness_or_length_mm grain edge_band miter_start miter_end]
        parts.each { |p| csv << p.values_at(:id,:cabinet,:type,:mode,:name,:kind,:material,:w,:h,:t,:grain,:edge_band,:miter_start,:miter_end) }
      end
      CSV.open(File.join(directory,'machining.csv'),'w') do |csv|
        csv << %w[operation_id cabinet part face edge x_mm y_mm diameter_mm depth_mm tool recipe status]
        operations.each { |o| csv << o.values_at(:id,:cabinet,:part,:face,:edge,:x,:y,:diameter,:depth,:tool,:recipe,:status) }
      end
      CSV.open(File.join(directory,'hardware.csv'),'w') do |csv|
        csv << %w[cabinet hardware quantity recipe]
        data[:cabinets].each { |c| c[:hardware].group_by { |h| [h[:name],h[:recipe]] }.each { |(n,r),hs| csv << [c[:id],n,hs.sum { |h| h[:quantity] },r] } }
      end
      CSV.open(File.join(directory,'profile_cuts.csv'),'w') do |csv|
        csv << %w[part_id cabinet profile length_mm miter_start miter_end stock_mm]
        parts.select { |p| p[:kind]=='profile' }.each { |p| csv << p.values_at(:id,:cabinet,:section,:cut_length,:miter_start,:miter_end,:stock_length) }
      end
      parts.each { |p| part_dxf(p,File.join(pd,"#{p[:id]}.dxf")) if p[:kind]=='panel' }
      nested=sheets(parts); sd=File.join(directory,'nested_dxf'); FileUtils.mkdir_p(sd)
      bar_plan=bars(parts); AJBoardScaffold.write_json(File.join(directory,'bar_nesting.json'),bar_plan)
      nested[:sheets].each_with_index do |b,i|
        dxf(File.join(sd,format('sheet_%04d.dxf',i+1))) do |io|
          poly(io,AJBoardScaffold.rectangle(b[:width],b[:height]),'STOCK')
          b[:placements].each do |placement|
            p=placement[:part]; poly(io,p[:outline].map { |x,y| transform_uv(x,y,placement) },'CUT_OUTER')
            p[:holes].each { |hole| poly(io,hole.map { |x,y| transform_uv(x,y,placement) },'CUT_INNER') }
            p[:operations].each do |o|
              next if o[:face]=='EDGE' || o[:kind]!='drill'
              x,y=transform_uv(o[:x],o[:y],placement); circle(io,x,y,o[:diameter]/2.0,layer(o))
            end
            label(io,placement[:x]+8,placement[:y]+18,p[:id],8)
          end
        end
      end
      summary={status:release ? 'RELEASED' : 'ENGINEERING_PREVIEW_NOT_MACHINE_RELEASE',cabinets:data[:cabinets].size,parts:parts.size,operations:operations.size,sheets:nested[:sheets].size,profile_stocks:bar_plan[:stocks].size,rejected:nested[:rejected]+bar_plan[:rejected],warnings:data[:warnings],face_convention:'A = local z=0; B = local z=thickness. DXF A/B share the A-view datum; B requires a postprocessor flip. EDGE coordinates and depth are in machining.csv.',stock_note:'2440 x 1220, 10 mm margin, 4 mm kerf. Stock grain runs along 2440 mm X. Profile stock 6400 mm, 10 mm end trim, 3 mm kerf.',ovvo:'No guessed OVVO drilling. Supply a verified product-specific recipe before machining.'}
      summary[:stock_note]='2440 x 1220 mm sheets, 10 mm margin, 4 mm kerf, grain along X. Profile stock is specified per part in profile_cuts.csv: 6000 mm for shared run Gola, 6400 mm otherwise; 10 mm end trims and 3 mm kerf.'
      AJBoardScaffold.write_json(File.join(directory,'export_report.json'),summary)
      summary
    end
  end

  # Secure, versioned client contract. The legacy server cannot enforce this
  # contract; live billing remains unavailable until its ledger is upgraded.
  class TokenClient
    attr_reader :base_url
    def initialize(base_url:,access_token:)
      require 'net/http'; require 'uri'; require 'openssl'
      @uri=URI(base_url); @base_url=base_url.sub(%r{/$},'')
      raise ArgumentError,'Token service must use HTTPS without embedded credentials' unless @uri.scheme=='https' && @uri.host && !@uri.userinfo
      raise ArgumentError,'Authenticated access token required' if access_token.to_s.empty?
      @access_token=access_token
    end
    def request(path,body)
      uri=URI(@base_url+path); http=Net::HTTP.new(uri.host,uri.port); http.use_ssl=true; http.verify_mode=OpenSSL::SSL::VERIFY_PEER; http.open_timeout=10; http.read_timeout=25
      req=Net::HTTP::Post.new(uri.request_uri); req['Authorization']="Bearer #{@access_token}"; req['Content-Type']='application/json'; req.body=JSON.generate(body)
      response=http.request(req)
      raise "Token service rejected request (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      result=JSON.parse(response.body,symbolize_names:true)
      raise 'Invalid token response' unless result.is_a?(Hash) && result[:ok]==true
      result
    end
    def reserve(job,key:SecureRandom.uuid)
      canonical=JSON.generate(job.respond_to?(:data) ? job.data : job)
      result=request('/api/v1/jobs/reserve',{idempotency_key:key,job_sha256:Digest::SHA256.hexdigest(canonical),job:JSON.parse(canonical)})
      raise 'Missing server reservation' unless result[:reservation_id].is_a?(String) && !result[:reservation_id].empty?
      result
    end
    def commit(reservation_id,artifact_sha256)
      request('/api/v1/jobs/commit',{reservation_id:reservation_id,artifact_sha256:artifact_sha256})
    end
    def release(reservation_id)
      request('/api/v1/jobs/release',{reservation_id:reservation_id})
    end
  end
end

module AJBoardScaffold
  class Adapter
    attr_reader :root,:job,:cabinet_entities,:statistics,:zones
    def initialize(job)
      raise 'SketchUp Ruby API is required to build geometry' unless defined?(Sketchup::Model)
      @job=job.respond_to?(:data) ? job.data : job
      @model=Sketchup.active_model; @cache={}; @hardware_cache={}; @cabinet_entities=[]; @zones={}
      @statistics={parts:0,hardware:0,unique_solids:0,non_solid:[],errors:[]}
      @materials={}; @motions=[]
    end
    def mm(v); v.to_f/25.4; end
    def pt(v); Geom::Point3d.new(v.map { |n| mm(n) }); end
    def vec(v); Geom::Vector3d.new(v); end
    def pose(v)
      Geom::Transformation.translation(pt(v[0,3]))*Geom::Transformation.rotation(ORIGIN,Z_AXIS,v[3]*Math::PI/180)
    end
    def part_pose(p); Geom::Transformation.axes(pt(p[:o]),vec(p[:u]),vec(p[:v]),vec(p[:n])); end
    def material(name)
      @materials[name] ||= begin
        colors={'Carcass'=>[226,222,211],'Back'=>[213,208,195],'Drawer'=>[192,151,107],'ShelfBoard'=>[225,226,219],'Front'=>[45,87,87],'Aluminum'=>[177,186,191],'Graphite'=>[44,48,52],'Glass'=>[150,199,206],'Mirror'=>[160,181,192],'ACP'=>[231,235,232],'Timber'=>[167,114,71],'Worktop'=>[202,199,191],'Wall'=>[232,227,215],'Floor'=>[168,170,169],'Hardware'=>[132,139,144],'Drilling'=>[205,92,34],'Appliance'=>[48,53,58]}
        m=@model.materials["CM / #{name}"] || @model.materials.add("CM / #{name}")
        m.color=Sketchup::Color.new(*(colors[name] || colors['Hardware'])); m.alpha=0.32 if name=='Glass'; m
      end
    end
    def tag(name)
      @model.layers["CM / #{name}"] || @model.layers.add("CM / #{name}")
    end
    def face(entities,points)
      f=entities.add_face(points.map { |p| pt(p) }); raise 'Face construction failed' unless f; f
    end
    def prism(entities,outer,holes,length,miter_start=0,miter_end=0)
      if miter_start!=0 || miter_end!=0
        width=outer.map(&:first).max
        offset=proc { |u,angle| angle==45 ? u : angle==-45 ? width-u : 0 }
        start=outer.map { |u,v| [u,v,offset.call(u,miter_start)] }; finish=outer.map { |u,v| [u,v,length-offset.call(u,miter_end)] }
        face(entities,start); face(entities,finish)
        holes.each do |poly|
          a=face(entities,poly.map { |u,v| [u,v,offset.call(u,miter_start)] }); a.erase!
          b=face(entities,poly.map { |u,v| [u,v,length-offset.call(u,miter_end)] }); b.erase!
        end
        ([outer]+holes).each do |poly|
          poly.each_with_index do |(u,v),i|
            x,y=poly[(i+1)%poly.size]
            face(entities,[[u,v,offset.call(u,miter_start)],[x,y,offset.call(x,miter_start)],[x,y,length-offset.call(x,miter_end)],[u,v,length-offset.call(u,miter_end)]])
          end
        end
      else
        f=face(entities,outer.map { |u,v| [u,v,0] }); f.reverse! if f.normal.z<0
        holes.each { |poly| h=face(entities,poly.map { |u,v| [u,v,0] }); h.erase! }
        f.pushpull(mm(length))
      end
    end
    def geometry_key(p)
      Digest::SHA256.hexdigest(JSON.generate(p.slice(:outline,:holes,:t,:kind,:miter_start,:miter_end)))
    end
    def part_definition(p)
      key=geometry_key(p)
      @cache[key] ||= begin
        d=@model.definitions.add("CM Solid #{key[0,12]}")
        prism(d.entities,p[:outline],p[:holes],p[:t],p.fetch(:miter_start,0),p.fetch(:miter_end,0))
        @statistics[:unique_solids]+=1
        # Group#manifold? works on installed SketchUp versions older than the
        # newly added ComponentDefinition#manifold?. Use an instance check below.
        d
      end
    end
    def zone(name)
      @zones[name] ||= begin
        g=@root.definition.entities.add_group; g.name=name; g.set_attribute(DICT,'zone',name); g
      end
    end
    def begin_build
      @model.start_operation('Build Cabinex Master Studio',true)
      @root=@model.entities.add_group; @root.name=@job[:name]
      @root.set_attribute(DICT,'job_id',@job[:id]); @root.set_attribute(DICT,'version',VERSION)
      @root.set_attribute(DICT,'job',JSON.generate(@job))
      @hardware_tag=tag('Hardware'); @drilling_tag=tag('Drilling'); @drilling_tag.visible=false
      @room_tag=tag('Room walls'); @room_tag.visible=false
      @labels_tag=tag('Labels')
      @root
    end
    def add_cabinet(c,label:true)
      parent=zone(c[:exhibit] || c[:zone] || 'Custom cabinets')
      g=parent.definition.entities.add_group; g.name="#{c[:id]} / #{c[:name]} / #{c[:mode]}"; g.transformation=pose(c[:pose])
      g.set_attribute(DICT,'cabinet',JSON.generate(c)); g.set_attribute(DICT,'id',c[:id]); g.set_attribute(DICT,'kind','cabinet')
      motion_groups={}
      c[:motions].each do |m|
        owner=m[:parent] ? motion_groups.fetch(m[:parent]).entities : g.entities
        mg=owner.add_group; mg.name=m[:name]; mg.set_attribute(DICT,'motion',JSON.generate(m)); mg.set_attribute(DICT,'closed',mg.transformation.to_a); mg.set_attribute(DICT,'fraction',0.0)
        motion_groups[m[:id]]=mg; @motions << mg
      end
      c[:parts].each do |p|
        owner=p[:motion] ? motion_groups.fetch(p[:motion]).entities : g.entities
        instance=owner.add_instance(part_definition(p),part_pose(p)); instance.name="#{p[:id]} / #{p[:name]}"; instance.material=material(p[:material]); instance.set_attribute(DICT,'part',JSON.generate(p)); instance.set_attribute(DICT,'kind','part')
        if instance.respond_to?(:manifold?) && !instance.manifold?
          @statistics[:non_solid] << {part:p[:id],name:p[:name],definition:instance.definition.name}
        end
        @statistics[:parts]+=1
        # Drilling is an explicit preview overlay on its own tag; actual part
        # outlines/cutouts are solids. Bore subtraction is an optional detail
        # action on an individual cabinet, never confused with CNC approval.
        unless p[:operations].empty?
          dg=owner.add_group; dg.name="Drilling / #{p[:id]}"; dg.layer=@drilling_tag; dg.transformation=part_pose(p)
          p[:operations].each do |o|
            next if o[:face]=='EDGE' || o[:kind]!='drill'
            z=o[:face]=='A' ? -0.1 : p[:t]+0.1
            edges=dg.entities.add_circle(pt([o[:x],o[:y],z]),Z_AXIS,mm(o[:diameter]/2.0),12)
            edges.each { |e| e.material=material('Drilling') }
          end
        end
      end
      c[:hardware].each do |h|
        owner=h[:motion] ? motion_groups.fetch(h[:motion]).entities : g.entities
        add_hardware(owner,h)
      end
      if label && c[:zone]=='catalogue'
        t=parent.definition.entities.add_text(c[:label],pt([c[:pose][0],c[:pose][1]-c[:d]-250,0])); t.layer=@labels_tag
      end
      @cabinet_entities << g; g
    end
    def add_hardware(entities,h)
      key=JSON.generate(h.slice(:kind,:size,:recipe))
      d=@hardware_cache[key] ||= begin
        definition=@model.definitions.add("CM Hardware #{@hardware_cache.size+1}"); e=definition.entities
        if h[:kind]=='cylinder'
          circle=e.add_circle(ORIGIN,Z_AXIS,mm(h[:size][0]/2),16); f=e.add_face(circle); f.reverse! if f.normal.z<0; f.pushpull(mm(h[:size][1]))
        else
          prism(e,AJBoardScaffold.rectangle(h[:size][0],h[:size][1]),[],h[:size][2])
        end
        definition
      end
      transform=Geom::Transformation.translation(pt(h[:o]))
      if h[:kind]=='cylinder'
        n=vec(h[:axis]); helper=n.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
        u=helper.cross(n); u.normalize!; v=n.cross(u); v.normalize!
        transform=Geom::Transformation.axes(pt(h[:o]),u,v,n)
      end
      i=entities.add_instance(d,transform); i.name=h[:name]; i.layer=@hardware_tag
      i.material=material(h[:recipe]=='appliance-glass' ? 'Glass' : h[:recipe].start_with?('appliance') || h[:name].include?('envelope') ? 'Appliance' : 'Hardware')
      i.set_attribute(DICT,'hardware',JSON.generate(h)); @statistics[:hardware]+=1
    end
    def add_fixture(f)
      g=zone(f[:zone] || 'Room').definition.entities.add_group; g.name=f[:name]; g.transformation=pose(f[:pose])
      if f[:part]
        p=f[:part]; i=g.entities.add_instance(part_definition(p),part_pose(p)); i.name="#{p[:id]} / #{p[:name]}"; i.set_attribute(DICT,'part',JSON.generate(p)); i.set_attribute(DICT,'kind','part')
        @statistics[:non_solid] << {part:p[:id],name:p[:name]} unless i.manifold?
        @statistics[:parts]+=1
      else
        prism(g.entities,AJBoardScaffold.rectangle(f[:w],f[:d]),f[:holes] || [],f[:h])
        @statistics[:non_solid] << {part:f[:id],name:f[:name]} unless g.manifold?
      end
      g.material=material(f[:material]); g.set_attribute(DICT,'fixture',JSON.generate(f))
      g.layer=@room_tag if f[:material]=='Wall'; g
    end
    def finish_build
      @root.set_attribute(DICT,'statistics',JSON.generate(@statistics)); @model.commit_operation
      self
    end
    def abort_build(error)
      @model.abort_operation; @statistics[:errors] << "#{error.class}: #{error.message}"; AJBoardScaffold.log("BUILD FAILED: #{error.message}\n#{error.backtrace.first(8).join("\n")}")
    end
    def build!
      begin_build
      @job[:cabinets].each_with_index do |c,i|
        add_cabinet(c)
        AJBoardScaffold.log("Geometry #{i+1}/#{@job[:cabinets].size}") if i%40==0
      end
      @job[:fixtures].each { |f| add_fixture(f) }; finish_build
    rescue StandardError => e
      abort_build(e); raise
    end
    def show_zone(name)
      raise ArgumentError,"Unknown view #{name}" unless @zones[name]
      @zones.each { |n,g| g.hidden=(n!=name) }
      g=@zones[name]; center=g.bounds.center
      @model.active_view.camera=Sketchup::Camera.new(center+Geom::Vector3d.new(mm(-7000),mm(-10000),mm(8000)),center,Z_AXIS)
      @model.active_view.zoom(g); @model.active_view.refresh; name
    end
    def show_all
      @zones.each_value { |g| g.hidden=false }; @model.active_view.zoom(@root); @model.active_view.refresh
    end
    def motion_transform(m,fraction)
      pivot=pt(m[:pivot]); value=m[:travel]*fraction
      case m[:kind]
      when 'hinge' then Geom::Transformation.rotation(pivot,Z_AXIS,-m[:hand]*value*Math::PI/180)
      when 'lift' then Geom::Transformation.rotation(pivot,X_AXIS,-value*Math::PI/180)
      when 'fold' then Geom::Transformation.rotation(pivot,X_AXIS,value*Math::PI/180)
      when 'slide' then Geom::Transformation.translation([mm(m[:hand]*value),0,0])
      when 'drawer' then Geom::Transformation.translation([0,mm(-value),0])
      else raise "Unknown motion #{m[:kind]}"
      end
    end
    def set_motion(group,fraction)
      raise ArgumentError,'Open fraction must be between 0 and 1' unless fraction>=0 && fraction<=1
      m=JSON.parse(group.get_attribute(DICT,'motion'),symbolize_names:true)
      closed=Geom::Transformation.new(group.get_attribute(DICT,'closed'))
      group.transformation=closed*motion_transform(m,fraction); group.set_attribute(DICT,'fraction',fraction)
    end
    def animate(fraction,selection:nil)
      selected=selection || @model.selection.to_a
      @model.start_operation('Cabinex door and drawer position',true)
      targets=selected.empty? ? @cabinet_entities.select { |c| c.parent.instances.any? { |z| !z.hidden? } rescue true } : selected
      targets.each do |c|
        moving=[]; walk(c) { |e| moving << e if e.get_attribute(DICT,'motion') }
        interlock=moving.any? { |e| JSON.parse(e.get_attribute(DICT,'motion'),symbolize_names:true)[:requires_clear_front] }
        moving.each do |e|
          m=JSON.parse(e.get_attribute(DICT,'motion'),symbolize_names:true)
          f=interlock && fraction>0 && %w[hinge slide].include?(m[:kind]) ? 1.0 : fraction
          set_motion(e,f)
        end
      end
      @model.commit_operation; @model.active_view.refresh
    rescue StandardError
      @model.abort_operation; raise
    end
    def walk(entity,&block)
      yield entity
      if entity.respond_to?(:definition)
        entity.definition.entities.each { |e| walk(e,&block) if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      elsif entity.respond_to?(:entities)
        entity.entities.each { |e| walk(e,&block) if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      end
    end
    def audit!
      result={version:VERSION,cabinets:@cabinet_entities.size,parts:@job[:cabinets].sum { |c| c[:parts].size },hardware:@job[:cabinets].sum { |c| c[:hardware].size },unique_solids:@statistics[:unique_solids],non_solid:@statistics[:non_solid],motion_restore_failures:[],empty_cabinets:[],scope:'Part solid topology and exact motion restoration. Collision clearance and manufacturer machining approval are separate checks.'}
      @cabinet_entities.each do |g|
        result[:empty_cabinets] << g.name if g.entities.length.zero?
        walk(g) do |e|
          next unless e.get_attribute(DICT,'motion')
          original=e.transformation.to_a; old_fraction=e.get_attribute(DICT,'fraction',0.0)
          set_motion(e,1.0); set_motion(e,0.0); closed=e.get_attribute(DICT,'closed')
          result[:motion_restore_failures] << e.name unless e.transformation.to_a.zip(closed).all? { |a,b| (a-b).abs<1e-9 }
          set_motion(e,old_fraction); e.transformation=Geom::Transformation.new(original)
        end
      end
      AJBoardScaffold.write_json(File.join(HOME,'output','sketchup_validation.json'),result); result
    end
    def save!(path)
      # Save just our owned root definition; no existing user geometry is erased
      # or written back to the user's current document path.
      hidden=@zones.transform_values(&:hidden?)
      @zones.each_value { |g| g.hidden=false }
      # Retain the root instance and its job metadata when the SKP is reopened.
      @export_wrapper ||= @model.definitions.add('CM Saved Studio Container')
      @export_wrapper.entities.clear!
      saved_root=@export_wrapper.entities.add_instance(@root.definition,Geom::Transformation.new)
      saved_root.name=@root.name; saved_root.set_attribute(DICT,'job',JSON.generate(@job)); saved_root.set_attribute(DICT,'job_id',@job[:id]); saved_root.set_attribute(DICT,'version',VERSION)
      success=@export_wrapper.save_as(path)
      @zones.each { |n,g| g.hidden=hidden[n] }
      raise 'SketchUp could not save the studio component' unless success
      path
    end
    def capture(path)
      @model.active_view.write_image(filename:path,width:1800,height:1200,antialias:true,transparent:false)
    end
    def attach(root)
      @root=root
      root.definition.entities.each { |e| name=e.get_attribute(DICT,'zone'); @zones[name]=e if name }
      walk(root) { |e| @cabinet_entities << e if e.get_attribute(DICT,'cabinet'); @motions << e if e.get_attribute(DICT,'motion') }
      @hardware_tag=tag('Hardware'); @drilling_tag=tag('Drilling'); @room_tag=tag('Room walls'); @labels_tag=tag('Labels')
      @statistics[:parts]=@job[:cabinets].sum { |c| c[:parts].size }; @statistics[:hardware]=@job[:cabinets].sum { |c| c[:hardware].size }
      self
    end
  end

  def active_adapter
    return @adapter if @adapter && @adapter.root && @adapter.root.valid?
    if defined?(Sketchup)
      root=Sketchup.active_model.entities.find { |e| e.get_attribute(DICT,'job') }
      if root
        @adapter=Adapter.new(JSON.parse(root.get_attribute(DICT,'job'),symbolize_names:true)).attach(root); return @adapter
      end
    end
    raise 'Build or load a Cabinex Master job first.'
  end
  def build_showcase!
    raise 'Another build is already running' if @building
    @building=true
    log("Planning #{catalogue.size} families, four modes, and handled / Gola kitchen runs")
    job=make_showcase; @adapter=Adapter.new(job); @adapter.begin_build
    index=0; total=job.data[:cabinets].size
    # Chunk on SketchUp's UI event loop. No geometry calls from worker threads.
    tick=nil
    tick=proc do
      begin
        finish=[index+12,total].min
        while index<finish
          @adapter.add_cabinet(job.data[:cabinets][index]); index+=1
        end
        log("Built #{index}/#{total} cabinets")
        if index<total
          UI.start_timer(0.02,false,&tick)
        else
          job.data[:fixtures].each { |f| @adapter.add_fixture(f) }; @adapter.finish_build
          Sketchup.active_model.entities.each { |e| e.hidden=true if e!=@adapter.root && e.get_attribute(DICT,'job') }
          @adapter.audit!; @adapter.save!(File.join(HOME,'output','Cabinex_Master_Complete_Studio.skp'))
          @adapter.show_zone('Kitchen L / hybrid')
          @adapter.capture(File.join(HOME,'output','Kitchen_L_hybrid.png'))
          write_json(File.join(HOME,'output','showcase_job.json'),job.data)
          check_runs!
          log("COMPLETE: #{total} cabinets, #{@adapter.statistics[:parts]} parts. Studio saved.")
          @building=false
        end
      rescue StandardError => e
        @adapter.abort_build(e); @building=false
        write_json(File.join(HOME,'output','build_error.json'),{error:e.message,backtrace:e.backtrace})
      end
    end
    UI.start_timer(0.01,false,&tick); 'Showcase build started; see status bar and output/studio.log.'
  rescue StandardError
    @building=false; raise
  end
  def build_one!(type='base_gola',mode:'hybrid',**opts)
    job=Job.new("Cabinex Master / #{type}"); job.add(type,mode:mode,**opts); @adapter=Adapter.new(job).build!; @adapter.show_all; @adapter.audit!; @adapter.root
  end
    def build_room!(shape:'L',mode:'hybrid',width:5400,depth:4800,openings:[],front_system:'handled',finger_gap:25)
    job=Job.new("Cabinex Master / #{shape} kitchen"); append_kitchen(job,shape:shape,mode:mode,width:width,depth:depth,openings:openings,front_system:front_system,finger_gap:finger_gap); job.validate!
    @adapter=Adapter.new(job).build!; @adapter.show_all; @adapter.audit!; @adapter.root
  end
  def export!(directory=nil,release:false)
    directory ||= File.join(HOME,'output',"export_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    result=Export.package(active_adapter.job,directory,release:release); log("Exported #{result[:parts]} parts to #{directory}"); result
  end
  def export_selection!
    adapter=active_adapter; selected=Sketchup.active_model.selection.to_a
    selected=adapter.cabinet_entities.select { |c| c.parent.instances.any? { |z| !z.hidden? } rescue true } if selected.empty?
    cabinets=[]
    selected.each { |e| adapter.walk(e) { |g| s=g.get_attribute(DICT,'cabinet'); cabinets << JSON.parse(s,symbolize_names:true) if s } }
    raise 'Select a cabinet or kitchen group to export.' if cabinets.empty?
    data=deep(adapter.job); data[:cabinets]=cabinets.uniq { |c| c[:id] }; data[:fixtures]=[]
    ids=data[:cabinets].map { |c| c[:id] }
    complete_runs=adapter.job[:runs].select do |r|
      members=adapter.job[:cabinets].select { |c| c[:run]==r[:id] }
      !members.empty? && members.all? { |c| ids.include?(c[:id]) }
    end.map { |r| r[:id] }
    data[:runs]=adapter.job[:runs].select { |r| complete_runs.include?(r[:id]) }
    data[:fixtures]=adapter.job[:fixtures].select { |f| complete_runs.include?(f[:run]) }
    data[:warnings] << 'Shared run parts are included only for complete selected runs; select the complete kitchen to export every plinth, filler and Gola rail.'
    dir=File.join(HOME,'output',"selection_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    Export.package(data,dir); log("Exported selected cabinets to #{dir}"); dir
  end
  def open_fronts!(fraction=0.65); active_adapter.animate(fraction); end
  def close_fronts!; active_adapter.animate(0.0); end
  def connect_tokens!(base_url:,access_token:)
    @token_client=TokenClient.new(base_url:base_url,access_token:access_token)
    'Token client configured for this SketchUp session. Credentials are not written to disk.'
  end
  def generate_paid!(job,client:nil)
    client ||= @token_client
    raise 'Connect the upgraded authenticated token service first.' unless client
    job.validate! if job.respond_to?(:validate!)
    data=job.respond_to?(:data) ? job.data : job
    directory=File.join(HOME,'output',"paid_#{safe_name(data[:id])}"); FileUtils.mkdir_p(directory)
    journal_path=File.join(directory,'reservation.json')
    raise 'This job already has a billing journal. Reconcile it before retrying.' if File.exist?(journal_path)
    key=SecureRandom.uuid; journal={state:'reserving',idempotency_key:key,job_id:data[:id]}; write_json(journal_path,journal)
    # A timeout is indeterminate. The persisted key must be reconciled with the
    # server; creating a second charge or silently granting access is forbidden.
    reservation=client.reserve(data,key:key)
    journal.merge!(state:'reserved',reservation_id:reservation[:reservation_id]); write_json(journal_path,journal)
    begin
      @adapter=Adapter.new(data).build!; artifact=File.join(directory,'cabinet_job.skp'); @adapter.save!(artifact)
      digest=Digest::SHA256.file(artifact).hexdigest
    rescue StandardError=>e
      journal.merge!(state:'release_pending',error:e.message); write_json(journal_path,journal)
      begin; client.release(reservation[:reservation_id]); journal[:state]='released'; write_json(journal_path,journal); rescue StandardError; end
      raise
    end
    journal.merge!(state:'commit_pending',artifact_sha256:digest); write_json(journal_path,journal)
    client.commit(reservation[:reservation_id],digest)
    journal[:state]='committed'; write_json(journal_path,journal); @adapter.show_all; artifact
  end
  def reconcile_tokens!(journal_path,client:nil)
    client ||= @token_client; raise 'Token session required' unless client
    j=JSON.parse(File.read(journal_path),symbolize_names:true)
    case j[:state]
    when 'commit_pending'
      client.commit(j.fetch(:reservation_id),j.fetch(:artifact_sha256)); j[:state]='committed'
    when 'release_pending'
      client.release(j.fetch(:reservation_id)); j[:state]='released'
    else
      raise 'This journal requires server-side status reconciliation using its original idempotency key.'
    end
    write_json(journal_path,j); j[:state]
  end
  def view!(name); active_adapter.show_zone(name); end
  def edit_selected!
    model=Sketchup.active_model; entity=model.selection.find { |e| e.get_attribute(DICT,'cabinet') }
    raise 'Select one top-level Cabinex Master cabinet.' unless entity
    old=JSON.parse(entity.get_attribute(DICT,'cabinet'),symbolize_names:true)
    input=UI.inputbox(['Width (mm)','Height (mm)','Depth (mm)','Construction'],old.values_at(:w,:h,:d,:mode),['','','',MODES.join('|')],"Edit #{old[:name]}")
    return unless input
    fresh=Cabinet.new(old[:type],mode:input[3],w:Float(input[0]),h:Float(input[1]),d:Float(input[2]),id:old[:id],pose:old[:pose],options:old[:options]).data
    fresh.merge!(old.slice(:zone,:exhibit,:run,:front_span,:aligns_to,:label))
    raise 'Room cabinets share an alignment plan. Rebuild the room to change their dimensions.' if fresh[:run]
    a=active_adapter; model.start_operation('Edit Cabinex Master cabinet',true)
    replacement=a.add_cabinet(fresh); replacement.transformation=entity.transformation
    entity.erase!; a.cabinet_entities.delete(entity)
    index=a.job[:cabinets].index { |c| c[:id]==fresh[:id] }; a.job[:cabinets][index]=fresh
    a.root.set_attribute(DICT,'job',JSON.generate(a.job)); model.selection.clear; model.selection.add(replacement); model.commit_operation
  rescue StandardError
    model.abort_operation if model; raise
  end
  def refresh_families!(families)
    a=active_adapter; model=Sketchup.active_model
    model.start_operation('Refresh Cabinex Master families',true)
    a.job[:cabinets].each_with_index do |old,index|
      next unless families.include?(old[:type])
      fresh=Cabinet.new(old[:type],mode:old[:mode],w:old[:w],h:old[:h],d:old[:d],id:old[:id],pose:old[:pose],options:old[:options]).data
      fresh.merge!(old.slice(:zone,:exhibit,:run,:front_span,:aligns_to,:label))
      entity=a.cabinet_entities.find { |e| e.get_attribute(DICT,'id')==old[:id] }
      raise "Missing cabinet #{old[:id]}" unless entity
      a.add_cabinet(fresh,label:false); entity.erase!; a.cabinet_entities.delete(entity); a.job[:cabinets][index]=fresh
    end
    a.root.set_attribute(DICT,'job',JSON.generate(a.job)); model.commit_operation
    write_json(File.join(HOME,'output','showcase_job.json'),a.job)
    a.audit!; a.save!(File.join(HOME,'output','Cabinex_Master_Complete_Studio.skp')); true
  rescue StandardError
    model.abort_operation if model; raise
  end
  def refresh_run_fixtures!
    a=active_adapter; fresh=make_showcase.data
    raise 'Cabinet identifiers changed; rebuild the studio instead.' unless fresh[:cabinets].map { |c| c[:id] }==a.job[:cabinets].map { |c| c[:id] }
    changed=fresh[:cabinets].zip(a.job[:cabinets]).select { |c,old| c!=old }.map(&:first)
    fresh[:id]=a.job[:id]; fresh[:created_at]=a.job[:created_at]
    old=[]; a.walk(a.root) { |e| old << e if e.get_attribute(DICT,'fixture') }
    model=Sketchup.active_model; model.start_operation('Update Cabinex run closures',true)
    changed.each do |c|
      e=a.cabinet_entities.find { |g| g.get_attribute(DICT,'id')==c[:id] }
      raise "Missing cabinet #{c[:id]}" unless e
      a.add_cabinet(c,label:false); e.erase!; a.cabinet_entities.delete(e)
    end
    fresh[:fixtures].each { |f| a.add_fixture(f) }; old.each(&:erase!)
    a.job.replace(fresh); a.root.set_attribute(DICT,'job',JSON.generate(fresh)); model.commit_operation
    write_json(File.join(HOME,'output','showcase_job.json'),fresh); check_runs!
    a.audit!; a.save!(File.join(HOME,'output','Cabinex_Master_Complete_Studio.skp')); log("Run closures updated; #{changed.size} adjoining upper cabinets redivided."); true
  rescue StandardError
    model.abort_operation if model; raise
  end
  def show_dialog
    views=MODES.map { |m| "Catalogue #{m}" }+MODES.flat_map { |m| %w[I L U GALLEY H].map { |s| "Kitchen #{s} / #{m}" } }+%w[board hybrid].flat_map { |m| %w[I L U GALLEY H].map { |s| "Kitchen #{s} / #{m} / Gola" } }
    html=<<~HTML
      <!doctype html><html><head><meta charset="utf-8"><style>
      body{font:15px system-ui;background:#17282b;color:#edf2ed;margin:0;padding:28px}h1{font-size:25px;margin:0}p{color:#b8cbc6;line-height:1.55}label{display:block;margin-top:16px}select,input,textarea{box-sizing:border-box;width:100%;padding:10px;margin-top:5px;background:#284046;color:white;border:1px solid #58716e;border-radius:5px}button{padding:12px 16px;margin:16px 6px 0 0;border:0;border-radius:5px;background:#d0b785;color:#18272a;cursor:pointer}#status{white-space:pre-wrap;color:#ffd69a}.row{display:grid;grid-template-columns:1fr 1fr;gap:16px}</style></head><body>
      <h1>Cabinex Master Studio</h1><p>Cabinets, wardrobes and coordinated kitchens.</p>
      <label>Construction<select id="mode">#{MODES.map { |m| "<option>#{m}</option>" }.join}</select></label>
      <label>Cabinet family<select id="type">#{catalogue.map { |r| "<option value='#{r[:id]}'>#{r[:name]}</option>" }.join}</select></label>
      <button onclick="send('cabinet')">Create cabinet</button><button onclick="sketchup.edit()">Edit selected</button>
      <label>Kitchen shape<select id="shape"><option>I</option><option>L</option><option>U</option><option>GALLEY</option><option>H</option></select></label>
      <div class="row"><label>Front system<select id="front_system"><option value="handled">Finger handles</option><option value="gola">Continuous L / C Gola</option></select></label><label>Gola finger clearance (mm)<input id="finger_gap" type="number" value="25" min="20" max="40"></label></div>
      <div class="row"><label>Room width (mm)<input id="width" type="number" value="5400" min="1800"></label><label>Room depth (mm)<input id="depth" type="number" value="4800" min="1800"></label></div>
      <label>Openings: wall, door/window, position, width, sill, height (mm)<textarea id="openings" rows="3" placeholder="A, window, 1900, 1600, 1050, 950"></textarea></label>
      <button onclick="send('room')">Create kitchen</button><button onclick="sketchup.catalogue()">Build complete studio</button>
      <label>Studio view<select id="view">#{views.map { |v| "<option>#{v}</option>" }.join}</select></label>
      <button onclick="sketchup.gaps()">Check run gaps</button>
      <button onclick="sketchup.view(document.getElementById('view').value)">Show view</button><button onclick="sketchup.open()">Open selected</button><button onclick="sketchup.close()">Close selected</button><button onclick="sketchup.export()">Export selected</button><p id="status"></p>
      <script>function send(action){const p={};for(const k of ['mode','type','shape','width','depth','openings','front_system','finger_gap'])p[k]=document.getElementById(k).value;sketchup.build(action,JSON.stringify(p))}function status(t){document.getElementById('status').textContent=t}</script></body></html>
    HTML
    @dialog ||= UI::HtmlDialog.new(dialog_title:'Cabinex Master Studio',preferences_key:'AJBoardScaffoldStudio',scrollable:true,resizable:true,width:580,height:920,style:UI::HtmlDialog::STYLE_DIALOG)
    @dialog.set_html(html)
    safe=proc { |&b| begin; result=b.call; @dialog.execute_script("status(#{JSON.generate(result.to_s)})"); rescue StandardError => e; @dialog.execute_script("status(#{JSON.generate(e.message)})"); log(e.message); end }
    @dialog.add_action_callback('build') do |_ctx,action,json|
      safe.call do
        p=JSON.parse(json,symbolize_names:true)
        if action=='cabinet'
          build_one!(p[:type],mode:p[:mode]); 'Cabinet created.'
        else
          openings=p[:openings].lines.reject { |l| l.strip.empty? }.map do |line|
            a=line.split(',').map(&:strip); raise 'Each opening needs six comma-separated fields.' unless a.size==6
            {wall:a[0].upcase,kind:a[1].downcase,x:Float(a[2]),width:Float(a[3]),sill:Float(a[4]),height:Float(a[5])}
          end
          build_room!(shape:p[:shape],mode:p[:mode],width:Float(p[:width]),depth:Float(p[:depth]),openings:openings,front_system:p[:front_system],finger_gap:Float(p[:finger_gap])); 'Kitchen created; every run passed its gap check.'
        end
      end
    end
    @dialog.add_action_callback('catalogue') { safe.call { build_showcase! } }
    @dialog.add_action_callback('view') { |_ctx,name| safe.call { view!(name) } }
    @dialog.add_action_callback('open') { safe.call { open_fronts!; 'Fronts opened. Review clearances before operating actual hardware.' } }
    @dialog.add_action_callback('close') { safe.call { close_fronts!; 'Fronts closed.' } }
    @dialog.add_action_callback('export') { safe.call { export_selection! } }
    @dialog.add_action_callback('edit') { safe.call { edit_selected!; 'Edit complete.' } }
    @dialog.add_action_callback('gaps') { safe.call { check_runs! } }
    @dialog.show
  end
  def install_menu
    return if @menu_installed
    menu=UI.menu('Extensions').add_submenu('Cabinex Master Studio')
    { 'Open studio'=>proc { show_dialog }, 'Build complete showcase'=>proc { build_showcase! }, 'Open selected fronts'=>proc { open_fronts! }, 'Close selected fronts'=>proc { close_fronts! }, 'Edit selected cabinet'=>proc { edit_selected! }, 'Export selected cabinets'=>proc { export_selection! }, 'Show drilling'=>proc { Sketchup.active_model.layers['CM / Drilling'].visible=true }, 'Hide drilling'=>proc { Sketchup.active_model.layers['CM / Drilling'].visible=false }, 'Audit geometry'=>proc { puts JSON.pretty_generate(active_adapter.audit!) } }.each do |label,action|
      menu.add_item(label) { begin; action.call; rescue StandardError=>e; log(e.message); UI.messagebox(e.message); end }
    end
    @menu_installed=true
  end
  # Scaffold menu disabled: AJBoardKitchen owns the UI.
end
