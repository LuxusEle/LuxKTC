# frozen_string_literal: true
# All dimensions in this file are millimetres. SketchUp conversion lives in view.rb.
require_relative 'vendor/master_scaffold' unless defined?(AJBoardScaffold)
require 'time'
require_relative 'layout'

module AJBoardKitchen
  extend self
  remove_const(:ROOT) if const_defined?(:ROOT, false)
  ROOT = File.expand_path(__dir__)
  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '0.4.1-aspire-dxf'
  DICT = 'AJBoardKitchenTest' unless const_defined?(:DICT)
  S = AJBoardScaffold unless const_defined?(:S)
  X=S::X unless const_defined?(:X)
  Y=S::Y unless const_defined?(:Y)
  Z=S::Z unless const_defined?(:Z)
  NY=S::NY unless const_defined?(:NY)
  remove_const(:DEFAULTS) if const_defined?(:DEFAULTS, false)
  DEFAULTS = {
    joinery:'minifix', edge:1.0, front_edge:1.0, hinge:'cup35_screw',
    back_thickness:6.0, back_groove_depth:5.0,
    upper_finger_gap:25.0, upper_cover_recess:30.0, label_detail:'compact',
    cam_setback:34.0, cam_depth:12.0, bolt_dia:5.0, bolt_depth:12.0,
    cup_offset:22.5, cup_depth:13.0, cup_pitch:45.0, cup_fix_offset:9.5,
    hinge_plate_row:37.0, hinge_plate_pitch:32.0,
    runner_length:500.0, runner_clearance:42.0, runner_row:37.0,
    runner_pitch:224.0, runner_hole_height:15.0,
    hook_inset:7.0, hook_height:11.0, hook_depth:10.0,
    lock_inset:24.0, lock_front:30.0, lock_pitch:32.0,
    dowel_dia:8.0,dowel_edge_depth:20.0,dowel_face_depth:12.0,
    rafix_depth:12.7,rafix_axis:8.0,
    sheet_w:2440.0, sheet_h:1220.0, kerf:4.0, margin:10.0, edge_overrides:{},cabinet_overrides:{}
  }.freeze

  def settings(input={})
    c=DEFAULTS.merge(input.transform_keys(&:to_sym))
    raise 'Select a supported connector recipe' unless %w[minifix screw minifix_dowel rafix ovvo_od830 dowel].include?(c[:joinery])
    raise 'Select a supported hinge' unless %w[cup35_screw cup35_dowel none].include?(c[:hinge])
    raise 'Select compact or full labels' unless %w[compact full].include?(c[:label_detail])
    DEFAULTS.each { |k,v| c[k]=Float(c[k]) if v.is_a?(Numeric) }
    raise 'Invalid cabinet options' unless c[:cabinet_overrides].is_a?(Hash)
    ids=Layout::BASE.map(&:first)+Layout::UPPER.map(&:first)
    c[:cabinet_overrides]=c[:cabinet_overrides].to_h do |id,options|
      raise 'Unknown cabinet or invalid options' unless ids.include?(id.to_s) && options.is_a?(Hash)
      o=options.transform_keys(&:to_sym)
      raise 'Unknown cabinet setting' unless (o.keys-%i[w h d joinery hinge edge front_edge locked]).empty?
      %i[w h d edge front_edge].each { |key| o[key]=Float(o[key]) if o.key?(key) }
      raise 'Invalid cabinet size' unless o.values.grep(Numeric).all?(&:finite?)
      %i[edge front_edge].each { |key| raise 'Band must be 0 to 2 mm' if o.key?(key) && !o[key].between?(0,2) }
      raise 'Invalid width lock' if o.key?(:locked) && ![true,false].include?(o[:locked])
      raise 'Unknown connector' if o[:joinery] && !%w[minifix screw minifix_dowel rafix ovvo_od830 dowel].include?(o[:joinery])
      raise 'Unknown hinge' if o[:hinge] && !%w[cup35_screw cup35_dowel none].include?(o[:hinge])
      [id.to_s,o]
    end
    {dowel_dia:6..8,dowel_edge_depth:15..25,dowel_face_depth:8..14,rafix_depth:12.7..14.4,rafix_axis:8..9.5}.each do |k,r|
      raise "#{k}: outside allowed range" unless r.cover?(c[k])
    end
    raise 'Invalid edge selections' unless c[:edge_overrides].is_a?(Hash)
    c[:edge_overrides]=c[:edge_overrides].to_h do |id,edges|
      raise 'Invalid edge selection' unless edges.is_a?(Hash)
      clean=edges.to_h do |side,value|
        side=side.to_s;v=Float(value)
        raise 'Band sides must be L/R/B/T, thickness 0 to 2 mm' unless %w[L R B T].include?(side) && v.finite? && v.between?(0,2)
        [side,v]
      end
      [id.to_s,clean.reject { |_,v| v==0 }]
    end
    raise 'Dimensions must be finite' unless c.values.grep(Numeric).all?(&:finite?)
    raise 'Back thickness must be 4 to 9 mm' unless c[:back_thickness].between?(4,9)
    raise 'Back groove depth must be 3 to 8 mm' unless c[:back_groove_depth].between?(3,8)
    raise 'Upper finger gap must be 20 to 40 mm' unless c[:upper_finger_gap].between?(20,40)
    raise 'Upper cover recess must be 25 to 45 mm' unless c[:upper_cover_recess].between?(25,45)
    {edge:0..2,front_edge:0..2,cam_setback:24..40,cam_depth:10..14,bolt_dia:3..8,bolt_depth:8..15,cup_offset:21..25,cup_depth:11..14,cup_pitch:38..52,cup_fix_offset:5..12,hinge_plate_row:32..45,hinge_plate_pitch:24..48,runner_length:400..500,runner_clearance:40..50,runner_row:30..50,runner_pitch:160..320,runner_hole_height:10..25,hook_inset:5..20,hook_height:8..25,hook_depth:6..12,lock_inset:18..45,lock_front:20..60,lock_pitch:20..40,sheet_w:2200..3000,sheet_h:1100..1600,kerf:3..8,margin:5..25}.each do |k,r|
      raise "#{k}: must be #{r.begin} to #{r.end} mm" unless r.cover?(c[k])
    end
    c
  end

  class Board < S::Cabinet
    def cfg; @data[:options][:config]; end
    def validate!
      raise 'Duplicate part identifiers' unless parts.map { |p| p[:id] }.uniq.size==parts.size
      parts.each do |p|
        raise "Empty contour: #{p[:name]}" unless p[:outline].size>=3 && S::Math3.area(p[:outline])>0.1
        raise "Non-orthogonal frame: #{p[:name]}" unless S::Math3.dot(p[:u],p[:v]).abs<1e-6 && S::Math3.dot(p[:u],p[:n]).abs<1e-6 && S::Math3.dot(p[:v],p[:n]).abs<1e-6
      end
      AJBoardKitchen.validate_job(cabinets:[@data])
      @data[:warnings] << 'Hardware recipes require a matching SKU, material trial and workshop approval.'
      @data[:warnings] << 'Rafix 20: open-edge housing; adjustable depth/axis must match your exact fitting. Default 16 mm-family drilling is a test in 18 mm stock.' if cfg[:joinery]=='rafix'
      true
    end
    def panel(*args,**kwargs)
      @part_serial=(@part_serial||0)+1
      p=super
      p[:id]="#{@data[:id]}-P#{@part_serial}"
      p
    end
    def board_joints; end # Generated after all fixed shelves and decks exist.
    def handle(*args); super unless @gola; end
    def doors(**kwargs)
      kwargs[:count]=2 if @recipe==:hood
      if @wall
        # Full-height fronts overhang the raised carcass and its underside cover.
        kwargs[:z]=@upper_front_base+1.5
        kwargs[:h]=@upper_front_height-3
      end
      super(**kwargs)
    end

    def build
      if @wall
        @upper_front_base=@z;@upper_front_height=@h
        rise=1.5+cfg[:upper_finger_gap]+18.0
        @z+=rise;@h-=rise
        @data[:carcass_base_z]=@z;@data[:carcass_height]=@h
        @data[:upper_underside]={cover_thickness:18.0,finger_gap:cfg[:upper_finger_gap],front_recess:cfg[:upper_cover_recess],profile_opening:'down',front_height:@upper_front_height}
      end
      if @data[:type]=='tall_oven_micro'
        carcass
        drawers(2,z:@z+1.5,height:497,gola:true)
        [500,1110,1720].each_with_index { |v,i| shelf(@z+v,"Fixed appliance shelf #{i+1}",depth:@d-40) }
        [518,1128].each_with_index do |v,i|
          appliance("Oven #{i+1}",20,-@d+8,@z+v,560,@d-40,590)
          hw("Oven #{i+1} fascia",[3,-@d-18,@z+v],size:[594,16,590],recipe:'appliance-envelope')
          hw("Oven #{i+1} window",[60,-@d-20,@z+v+100],size:[480,2,360],recipe:'appliance-glass')
        end
        doors(z:@z+1740,h:@h-1743,count:1)
        @data[:warnings] << 'Two 590 mm oven envelopes. Confirm both installation/ventilation drawings.'
      elsif @data[:id]=='B05'
        carcass; drawers(2,gola:true); gola_profiles
        hw('Hob glass',[30,-@d+45,@z+@h+31],size:[540,450,6],recipe:'appliance-glass')
        @data[:warnings] << 'Hob and hood envelopes are provisional. Check appliance cutouts and clearances.'
      else
        super
      end
      restore_board_construction
      fixed_joints
      upper_underside if @wall
      finish_metadata
    end

    def upper_underside
      z=@upper_front_base+1.5+cfg[:upper_finger_gap]
      front=-@d+cfg[:upper_cover_recess]
      cover=panel('Upper underside cover - 18 mm',@w,@d-cfg[:upper_cover_recess],18,[0,front,z])
      cover[:number_after_legacy]=true
      cover[:upper_cover]=true
      has_doors=parts.any? { |p| p[:material]=='Front' && p[:motion] }
      has_pull=has_doors && @recipe!=:hood
      cover[:upper_cover_no_pull]=!has_pull
      @data[:upper_underside][:finger_pull]=has_pull
      @data[:upper_underside][:profile_opening]=has_pull ? 'down' : 'none'
      if has_pull
        # Cross-section in Y/Z: top flange points toward the door; rear leg
        # covers the front edge of the 18 mm cover. The cavity is OPEN DOWN.
        # The profile is fixed to the cabinet, never attached to the door.
        width=cfg[:upper_cover_recess]-2.0;wall=1.5
        outline=[[0,18],[width,18],[width,0],[width-wall,0],[width-wall,18-wall],[0,18-wall]]
        pull=panel('Upper underside L finger pull - opens down',width,18,@w,[0,-@d+2,z],Y,Z,X,material:'Aluminum',outline:outline,grain:'none')
        pull.merge!(kind:'profile',section:'upper_l_pull',cut_length:@w,stock_length:6400.0,miter_start:0,miter_end:0,number_after_legacy:true)
        @data[:front_system]='upper_underside_pull'
      end
      if @recipe==:hood
        # Provisional cassette opening, aligned through BOTH horizontal boards.
        # Keep solid material ahead of the rear back groove and around fixings.
        cut_x=75.0;cut_y=front+20.0;cut_w=@w-150.0;cut_d=-50.0-cut_y
        [@floor,cover].each do |p|
          px=cut_x-p[:o][0];py=cut_y-p[:o][1]
          p[:holes] << S.rectangle(cut_w,cut_d).map { |x,y| [px+x,py+y] }
        end
        extractor=hardware.find { |h| h[:name]=='Extractor envelope' }
        if extractor
          extractor[:o]=[cut_x,cut_y,z];extractor[:size]=[cut_w,cut_d,240.0]
        end
        @data[:upper_underside][:hood_opening]={x:cut_x,y:cut_y,w:cut_w,d:cut_d,status:'Confirm cassette manufacturer cutout'}
      end
      # Screws run down through the carcass bottom into the cover. Their pilots
      # stay outside the cassette aperture and clear the rear groove.
      [50.0,@w-50.0].product([front+45.0,-45.0]).each do |x,y|
        drill(@floor,x-@floor[:o][0],y-@floor[:o][1],4,18,face:'B',recipe:'review-upper-cover-clearance')
        drill(cover,x-cover[:o][0],y-cover[:o][1],3,12,face:'B',recipe:'review-upper-cover-pilot')
        hw('Upper cover fixing screw',[x,y,@z+18-30],size:[4,30,4],kind:'cylinder',axis:Z,recipe:'review-upper-cover-screw')
      end
    end

    # Restore the original Shotgun/hybrid board dimensions after the scaffold
    # recipe has run. This retains existing part IDs and edge selections.
    def groove(p,x,y,w,h,face)
      p[:operations] << {id:"#{p[:id]}-O#{p[:operations].size+1}",kind:'groove',
        x:x.to_f,y:y.to_f,w:w.to_f,h:h.to_f,depth:cfg[:back_groove_depth],
        face:face,tool:'straight-groove',recipe:'board-back-groove',status:'REVIEW'}
    end

    def restore_board_construction
      bt=cfg[:back_thickness];gd=cfg[:back_groove_depth];back_front=-@t-bt
      parts.select { |p| %w[Bottom Top].include?(p[:name]) }.each do |p|
        p[:h]=@d;p[:outline]=S.rectangle(p[:w],p[:h])
      end
      front=parts.find { |p| p[:name]=='Front stretcher' }
      rear=parts.find { |p| p[:name]=='Rear stretcher' }
      [front,rear].compact.each { |p| p[:h]=100.0;p[:outline]=S.rectangle(p[:w],p[:h]) }
      rear[:o][1]=-100.0 if rear
      if @recipe==:sink
        front.merge!(name:'Sink front rail',h:50.0,o:[@t,-@d+48,@z+@h-50],u:X,v:Z,n:NY,outline:S.rectangle(@w-2*@t,50))
        rear.merge!(name:'Sink rear top rail',h:50.0,o:[@t,0,@z+@h-50],u:X,v:Z,n:NY,outline:S.rectangle(@w-2*@t,50))
        panel('Rear bottom vertical stretcher',@w-2*@t,100,18,[@t,0,@z+@t],X,Z,NY)
        @data[:back_construction]='Open sink service back with upright top rails and lower rear stretcher'
      else
        back=parts.find { |p| p[:material]=='Back' }
        back ||= panel('Back',@w-2*@t,@h-2*@t,bt,[@t,-@t,@z+@t],X,Z,NY,material:'Back',grain:'v')
        bw=@w-2*@t+2*gd;bh=@h-2*@t+2*gd
        back.merge!(name:'Back (grooved)',w:bw,h:bh,t:bt,o:[@t-gd,-@t,@z+@t-gd],outline:S.rectangle(bw,bh))
        @sides.each_with_index { |p,i| groove(p,@d-@t-bt,0,bt,@h,i==0 ? 'B' : 'A') }
        groove(@floor,0,@d-@t-bt,@floor[:w],bt,'B')
        top=rear||@top
        groove(top,0,back_front-top[:o][1],top[:w],bt,'A')
        panel('Rear bottom vertical stretcher',@w-2*@t,100,18,[@t,0,@z+@t],X,Z,NY)
        panel('Rear top vertical stretcher',@w-2*@t,100,18,[@t,0,@z+@h-@t-100],X,Z,NY)
        @data[:back_construction]={type:'grooved',thickness:bt,groove_depth:gd,rear_stretcher_height:100.0}
      end
      parts.select { |p| p[:material]=='Carcass' && p[:u]==X && p[:v]==Y && p[:name]=~/shelf/i }.each do |p|
        p[:h]=[p[:h],back_front-1-p[:o][1]].min
        p[:outline]=S.rectangle(p[:w],p[:h])
      end
      hardware.select { |h| h[:name]=='Extractor envelope' }.each { |h| h[:size][1]=[h[:size][1],back_front-1-h[:o][1]].min }
    end

    def front(*args,**kwargs)
      before=parts.length; hb=hardware.length
      mid=super
      p=parts[before..].find { |q| q[:material]=='Front' && q[:kind]=='panel' }
      return mid unless p && kwargs.fetch(:kind,'hinge')=='hinge'
      p[:operations].clear
      hardware.slice!(hb,hardware.length-hb)
      return mid if cfg[:hinge]=='none'
      hand=kwargs.fetch(:hand,1); hx=hand==1 ? cfg[:cup_offset] : p[:w]-cfg[:cup_offset]
      count=p[:h]>1800 ? 4 : p[:h]>1000 ? 3 : 2
      count.times do |i|
        hy=100+(p[:h]-200)*i/(count-1).to_f
        drill(p,hx,hy,35,cfg[:cup_depth],face:'A',recipe:'review-cup35')
        fixx=hx+(hand==1 ? -cfg[:cup_fix_offset] : cfg[:cup_fix_offset])
        [-1,1].each { |sign| drill(p,fixx,hy+sign*cfg[:cup_pitch]/2,cfg[:hinge]=='cup35_dowel' ? 8 : 2.5,10,face:'A',recipe:'review-hinge-fixing') }
        side=@sides[hand==1 ? 0 : 1]
        [-1,1].each { |sign| drill(side,cfg[:hinge_plate_row],p[:o][2]-@z+hy+sign*cfg[:hinge_plate_pitch]/2,5,12,face:hand==1 ? 'B' : 'A',recipe:'review-hinge-plate') }
        hw('Concealed hinge cup',S::Math3.local(p,[hx,hy,0]),size:[35,cfg[:cup_depth],35],kind:'cylinder',axis:NY,motion:mid,recipe:'review-cup35')
        hw('Hinge mounting plate',[hand==1 ? 18 : @w-21,-@d+cfg[:hinge_plate_row]-10,p[:o][2]+hy-22],size:[3,20,44],recipe:'review-hinge-plate')
      end
      mid
    end

    def drawers(count,x:@t,w:@w-2*@t,z:@z+3,height:@h-6,internal:false,gola:false)
      gola ||= @gola; gap=gola ? 25.0 : 3.0
      height=[height,@h-28].min if @h<=900
      fh=(height-gap*(count-1))/count
      count.times do |i|
        zz=z+i*(fh+gap); mid=front(1.5,zz,@w-3,fh,name:"Drawer face #{i+1}",kind:'drawer')
        # Test undermount recipe: internal width = cabinet opening - selected deduction.
        inner=w-cfg[:runner_clearance]; outer=inner+30; bx=x+(w-outer)/2
        len=cfg[:runner_length]-10; by=-@d+20; bz=zz+35; bh=[fh-60,180].min
        panel('Drawer left',len,bh,15,[bx,by,bz],Y,Z,X,material:'Drawer',motion:mid)
        panel('Drawer right',len,bh,15,[bx+outer-15,by,bz],Y,Z,X,material:'Drawer',motion:mid)
        panel('Drawer inner front',inner,bh-13,15,[bx+15,by+15,bz+13],X,Z,NY,material:'Drawer',motion:mid)
        back=panel('Drawer back - hook drilling',inner,bh-13,15,[bx+15,by+len,bz+13],X,Z,NY,material:'Drawer',motion:mid)
        [cfg[:hook_inset],inner-cfg[:hook_inset]].each { |xx| drill(back,xx,cfg[:hook_height],6,cfg[:hook_depth],face:'A',recipe:'review-undermount-rear-hook') }
        bottom=panel('Drawer bottom',inner,len-30,9,[bx+15,by+15,bz+13],material:'Drawer',motion:mid)
        [cfg[:lock_inset],inner-cfg[:lock_inset]].each do |xx|
          [cfg[:lock_front],cfg[:lock_front]+cfg[:lock_pitch]].each { |yy| drill(bottom,xx,yy,2.5,6,face:'A',recipe:'review-undermount-locking-plate') }
        end
        @sides.each_with_index do |side,si|
          [cfg[:runner_row],cfg[:runner_row]+cfg[:runner_pitch]].each { |row| drill(side,row,bz-@z+cfg[:runner_hole_height],3,12,face:si==0 ? 'B' : 'A',recipe:'review-undermount-cabinet-fixing') }
          rx=si==0 ? bx : bx+outer-18
          hw('Undermount runner',[rx,by,bz-12],size:[18,cfg[:runner_length],20],recipe:'review-undermount-runner')
          hw('Undermount locking plate',[si==0 ? bx+15 : bx+outer-55,by+20,bz+4],size:[40,55,9],motion:mid,recipe:'review-undermount-lock')
        end
        # Drawer face attachment pilots: through the sub-front, blind into the face.
        sub=parts.find { |p| p[:motion]==mid && p[:name]=='Drawer inner front' }
        fp=parts.find { |p| p[:motion]==mid && p[:material]=='Front' }
        [50,inner-50].each do |xx|
          [35,[bh-45,65].max].uniq.each do |yy|
            drill(sub,xx,yy,4,15,face:'A',recipe:'review-drawer-front-fixing')
            drill(fp,bx+15+xx-fp[:o][0],bz+13+yy-fp[:o][2],3,10,face:'A',recipe:'review-drawer-front-pilot')
          end
        end
      end
    end

    def fixed_joints
      return unless @sides
      decks=parts.select { |p| p[:kind]=='panel' && p[:material]=='Carcass' && p[:u]==X && (p[:v]==Y || p[:name]=~/vertical stretcher|Sink .* rail/) && !p[:motion] && (p[:w]-(@w-36)).abs<0.1 }
      decks.each do |p|
        ys=p[:v]==Z && p[:h]>=100 ? [25,p[:h]-25] : p[:h]>150 ? [50,p[:h]-50] : [p[:h]/2]
        if cfg[:joinery]=='ovvo_od830' && ys.size>1
          steps=((ys.last-ys.first)/128.0).ceil
          ys=(0..steps).map { |i| ys.first+(ys.last-ys.first)*i/steps.to_f }
        end
        ys.each do |yy|
          [0,1].each do |si|
            edge=si==0 ? 'LEFT' : 'RIGHT'; px=si==0 ? 0 : p[:w]
            wp=S::Math3.local(p,[px,yy,p[:t]/2]); side=@sides[si]
            joint="#{p[:id]}-J#{si}-#{yy.to_i}"
            if %w[minifix minifix_dowel].include?(cfg[:joinery])
              cx=si==0 ? cfg[:cam_setback] : p[:w]-cfg[:cam_setback]
              # Bottom/top access is selected explicitly; side pilots share world coordinates.
              cf=p[:v]==Z ? 'B' : p[:o][2]>@z+@h-40 ? 'A' : 'B'
              drill(p,cx,yy,15,cfg[:cam_depth],face:cf,recipe:'review-minifix-cam')
              drill(p,px,yy,8,cfg[:cam_setback],face:'EDGE',edge:edge,recipe:'review-minifix-edge')
              drill(side,wp[1]+@d,wp[2]-@z,cfg[:bolt_dia],cfg[:bolt_depth],face:si==0 ? 'B' : 'A',recipe:'review-minifix-bolt')
              hw('Minifix cam',S::Math3.local(p,[cx,yy,cf=='A' ? 0 : p[:t]-cfg[:cam_depth]]),size:[15,cfg[:cam_depth],15],kind:'cylinder',axis:p[:n],recipe:'review-minifix')
              hw('Minifix bolt',wp,size:[5,cfg[:cam_setback],5],kind:'cylinder',axis:si==0 ? X : [-1,0,0],recipe:'review-minifix')
            elsif %w[ovvo_od830 dowel].include?(cfg[:joinery])
              connector_dowel(p,side,si,yy,joint,ovvo:cfg[:joinery]=='ovvo_od830')
              next
            elsif cfg[:joinery]=='rafix'
              # Open-edge D20 housing. Axis is measured from the entry face,
              # not assumed to be at half panel thickness.
              cf=p[:v]==Z ? 'B' : p[:o][2]>@z+@h-40 ? 'A' : 'B'
              zz=cf=='A' ? cfg[:rafix_axis] : p[:t]-cfg[:rafix_axis]
              wp=S::Math3.local(p,[px,yy,zz]);cx=si==0 ? 9.5 : p[:w]-9.5
              drill(p,cx,yy,20,cfg[:rafix_depth],face:cf,recipe:'review-rafix20-housing')
              p[:operations].last.merge!(open_edge:edge,joint:joint,contact:[px,yy,zz])
              drill(side,wp[1]+@d,wp[2]-@z,cfg[:bolt_dia],cfg[:bolt_depth],face:si==0 ? 'B' : 'A',recipe:'review-rafix20-bolt')
              side[:operations].last.merge!(joint:joint)
              hw('Rafix 20 housing',S::Math3.local(p,[cx,yy,cf=='A' ? 0 : p[:t]-cfg[:rafix_depth]]),size:[20,cfg[:rafix_depth],20],kind:'cylinder',axis:p[:n],recipe:'review-rafix20')
              hw('Rafix bolt',wp,size:[5,10,5],kind:'cylinder',axis:si==0 ? X : [-1,0,0],recipe:'review-rafix20')
              next
            else
              drill(side,wp[1]+@d,wp[2]-@z,5,18,face:si==0 ? 'A' : 'B',recipe:'review-screw-clearance')
              drill(side,wp[1]+@d,wp[2]-@z,9,2,face:si==0 ? 'A' : 'B',recipe:'review-screw-recess')
              drill(p,px,yy,3,32,face:'EDGE',edge:edge,recipe:'review-screw-pilot')
              hw('Assembly screw 5 x 50',[si==0 ? 0 : @w,wp[1],wp[2]],size:[5,50,5],kind:'cylinder',axis:si==0 ? X : [-1,0,0],recipe:'review-screw')
            end
            p[:operations].last[:joint]=joint; side[:operations].last[:joint]=joint
          end
        end
        if cfg[:joinery]=='minifix_dowel'
          # Independent paired dowels, offset from the cam/bolt rows. Never
          # duplicate a drilling template or stack two holes at one position.
          dy=ys.flat_map { |y| [y-32.0,y+32.0] }.select { |y| y>=12 && y<=p[:h]-12 && ys.all? { |cam| (cam-y).abs>=20 } }.uniq.sort
          dy=[p[:h]/2] if dy.empty? && ys.all? { |cam| (cam-p[:h]/2).abs>=20 }
          dy=dy.values_at(0,-1).uniq if dy.size>2
          @data[:warnings] << "#{p[:name]}: too narrow for a separate dowel row; Minifix only on this member." if dy.empty?
          dy.each do |y|
            [0,1].each { |si| connector_dowel(p,@sides[si],si,y,"#{p[:id]}-D#{si}-#{y}") }
          end
        end
      end
    end

    def connector_dowel(p,side,si,yy,joint,ovvo:false)
      edge=si==0 ? 'LEFT' : 'RIGHT';px=si==0 ? 0 : p[:w]
      wp=S::Math3.local(p,[px,yy,p[:t]/2])
      dia=ovvo ? 8.0 : cfg[:dowel_dia]
      ed=ovvo ? 18.0 : cfg[:dowel_edge_depth];fd=ovvo ? 13.0 : cfg[:dowel_face_depth]
      recipe=ovvo ? 'review-ovvo-od830' : 'review-dowel'
      drill(p,px,yy,dia,ed,face:'EDGE',edge:edge,recipe:recipe+'-end')
      p[:operations].last[:joint]=joint
      drill(side,wp[1]+@d,wp[2]-@z,dia,fd,face:si==0 ? 'B' : 'A',recipe:recipe+'-face')
      side[:operations].last[:joint]=joint
      start=S::Math3.add(wp,[si==0 ? -fd : -ed,0,0])
      hw(ovvo ? 'OVVO OD830 connector' : 'Assembly dowel',start,size:[dia,ovvo ? 30.0 : ed+fd-1,dia],kind:'cylinder',axis:X,recipe:recipe)
    end

    def finish_metadata
      parts.each do |p|
        p[:category]=p[:kind]=='profile' ? 'Gola' : p[:material]=='Front' ? (p[:name].include?('Drawer') ? 'Drawer faces' : 'Doors') : p[:material]=='Drawer' ? 'Drawer boxes' : 'Carcass'
        p[:category]='Plinth' if p[:name].include?('plinth')
        p[:category]='Backs' if p[:material]=='Back'
        p[:category]='Stretchers' if p[:name]=~/stretcher|Sink .* rail/
        p[:category]='Upper covers' if p[:upper_cover]
        p[:category]='Finger pulls' if p[:section]=='upper_l_pull'
        p[:edges]={}
        if p[:kind]=='panel'
          ed=p[:material]=='Front' ? cfg[:front_edge] : cfg[:edge]
          list=if p[:material]=='Front' then %w[L R B T]
               elsif p[:upper_cover] then p[:upper_cover_no_pull] ? %w[L R B T] : %w[L R T]
               elsif p[:material]=='Carcass' && p[:u]==Y then ['L']
               elsif p[:material]=='Carcass' && p[:v]==Y then ['B']
               elsif p[:material]=='Drawer' && p[:v]==Z then ['T']
               else [] end
          list.each { |e| p[:edges][e]=ed if ed>0 }
        end
      end
    end
  end

  # Clip the nominal finished contour to the core blank after band allowance.
  def core_part(part)
    p=S.deep(part); return p unless p[:kind]=='panel'
    e=p[:edges]||{}; l=e.fetch('L',0); r=e.fetch('R',0); b=e.fetch('B',0); t=e.fetch('T',0)
    p[:finished_w]=p[:w]; p[:finished_h]=p[:h]
    poly=p[:outline]
    [[0,l,1],[0,p[:w]-r,-1],[1,b,1],[1,p[:h]-t,-1]].each do |ax,bound,sign|
      out=[]
      poly.each_with_index do |a,i|
        q=poly[(i+1)%poly.length]; ia=sign*(a[ax]-bound)>=-1e-8; ib=sign*(q[ax]-bound)>=-1e-8
        out << a if ia
        if ia!=ib
          f=(bound-a[ax])/(q[ax]-a[ax]); out << [a[0]+f*(q[0]-a[0]),a[1]+f*(q[1]-a[1])]
        end
      end
      poly=out
    end
    p[:outline]=poly.map { |x,y| [x-l,y-b] }.uniq
    p[:holes]=p[:holes].map { |loop| loop.map { |x,y| [x-l,y-b] } }
    p[:o]=S::Math3.local(p,[l,b,0]); p[:w]-=l+r; p[:h]-=b+t
    p[:operations].each do |o|
      o[:x]-=l; o[:y]-=b; o[:status]='REVIEW'
      o[:contact]=[o[:contact][0]-l,o[:contact][1]-b,o[:contact][2]] if o[:contact]
      if o[:kind]=='groove'
        x2=[o[:x]+o[:w],p[:w]].min;y2=[o[:y]+o[:h],p[:h]].min
        o[:x]=[o[:x],0].max;o[:y]=[o[:y],0].max
        o[:w]=x2-o[:x];o[:h]=y2-o[:y]
      elsif o[:face]=='EDGE'
        allowance=o[:edge]=='LEFT' ? l : r
        o[:x]=o[:edge]=='LEFT' ? 0 : p[:w]
        o[:depth]-=allowance # Edge boring is from the core cut edge, before banding.
      end
    end
    p
  end

  def make_job(input={})
    c=settings(input); cabinets=[]
    base,upper=Layout.specs(c)
    (base+upper).each do |r|
      local=c.merge(r[:options].slice(:joinery,:hinge,:edge,:front_edge))
      options={config:local,joinery:local[:joinery]}
      options[:front_system]='gola' unless r[:anchor]
      cab=Board.new(r[:type],id:r[:id],w:r[:w],h:r[:h],d:r[:d],pose:[r[:x],0,r[:z],0],options:options).data
      names={'B01'=>'Tall pantry','B02'=>'Two ovens + two drawers','B03'=>'Sink / two doors','B04'=>'Gola drawers','B05'=>'Hob / Gola drawers','B06'=>'Door cupboard','W03'=>'Cassette hood / paired doors'}
      cab[:name]=names[r[:id]] if names[r[:id]]
      cab[:name]="#{r[:w].round(2).to_s.sub(/\.0$/,'')} door cupboard" if r[:id]=='B06'
      cab[:width_locked]=r[:locked];cab[:width_anchor]=r[:anchor]
      cabinets << cab
    end
    width=base.last[:x]+base.last[:w]+24.0
    sink=base.find { |r| r[:id]=='B03' };hob=base.find { |r| r[:id]=='B05' }
    workfront=-(base.drop(2).map { |r| r[:d] }.max+40.0)
    wx=sink[:x]
    room={id:'R01',name:'Worktop and end scribes',mode:'board',w:width,h:2200,d:-workfront,pose:[0,0,0,0],motions:[],hardware:[],warnings:[],parts:[]}
    p=proc do |name,w,h,t,o,u,v,n,mat,holes=[]|
      {id:"R01-P#{room[:parts].size+1}",name:name,kind:'panel',w:w.to_f,h:h.to_f,t:t.to_f,o:o,u:u,v:v,n:n,outline:S.rectangle(w,h),holes:holes,material:mat,category:mat=='Worktop' ? 'Worktop' : 'Carcass',operations:[],edges:{},grain:'none'}
    end
    cutouts=[[sink,440.0,370.0,65.0],[hob,560.0,490.0,35.0]].map do |r,cw,ch,inset|
      cx=r[:x]-wx+(r[:w]-cw)/2;cy=-r[:d]+inset-workfront
      S.rectangle(cw,ch).map { |xx,yy| [cx+xx,cy+yy] }
    end
    room[:parts] << p.call('Worktop - TEST sink and hob cutouts',width-wx,-workfront+20,30,[wx,workfront,100+sink[:h]],X,Y,Z,'Worktop',cutouts)
    room[:parts] << p.call('Left scribe',24,base.first[:h],18,[0,-base.first[:d],100],X,Z,NY,'Front')
    room[:parts] << p.call('Right scribe',24,base.last[:h],18,[width-24,-base.last[:d],100],X,Z,NY,'Front')
    cabinets << room
    # Stable numbers independent of the nesting order and hardware choice.
    num=0;extra_parts=[]
    cabinets.each do |cab|
      cab[:parts]=cab[:parts].map do |part|
        part[:edges]=c[:edge_overrides][part[:id]] if part[:kind]=='panel' && c[:edge_overrides].key?(part[:id])
        extra=part.delete(:number_after_legacy)
        num+=1 unless extra
        result=core_part(part).merge(number:extra ? nil : format('P%03d',num),cabinet_id:cab[:id],cabinet_name:cab[:name])
        extra_parts << result if extra
        result
      end
      # The scaffold supplies short door-mounted finger pulls for non-base
      # recipes. They are not recessed Gola rails and do not belong in this
      # handleless test. Remove them after assigning numbers so existing panel
      # IDs, labels and per-part edge overrides continue to identify the same
      # physical parts. Retired profile numbers are deliberately left unused.
      cab[:parts].reject! { |part| part[:kind]=='profile' && part[:section]=='handle' }
      cab[:front_system]='handleless' if cab[:front_system]=='handled'
    end
    extra_parts.each { |part| num+=1;part[:number]=format('P%03d',num) }
    data={id:'AJ-BOARD-10FT',name:'AJ | 10 foot board Gola test',version:VERSION,settings:c,width:width,cabinets:cabinets,fixtures:[],status:'WORKSHOP TEST - hardware and appliance recipes require confirmation',notes:[
      'Face A = local z=0. Face B = local z=thickness. B DXFs mirror local X for a physical flip about local Y.',
      'Core cut dimensions exclude selected edgeband thickness; finished dimensions are listed separately.',
      'Per-part bands use local A-view sides L/R/B/T. Edge bores start at the core edge before banding.',
      'Undermount is an editable test recipe, not an approved Blum/other brand machining program.',
      'Locking plate holes are vertical test pilots. Angled brand-specific locking devices require a different recipe.',
      'Sink, hob, hood and ovens are envelopes/cutout tests; final appliance drawings govern.',
      "#{c[:back_thickness]} mm backs in #{c[:back_groove_depth]} mm deep grooves; 100 mm rear stretchers. Sink retains an open service back.",
      'Open shelving is upper only. Oven back/vent openings must follow the selected appliance drawings.',
      "Upper fronts keep their selected height; carcasses rise by #{c[:upper_finger_gap]+19.5} mm. Underside covers are 18 mm; clear lower reveal #{c[:upper_finger_gap]} mm; front recess #{c[:upper_cover_recess]} mm. L pulls open down on regular upper cupboards only. Tall, hood and open units have no finger pulls."
    ]}
    validate_job(data); data
  end

  def parts(job); job[:cabinets].flat_map { |c| c[:parts] }; end
  def panels(job); parts(job).select { |p| p[:kind]=='panel' }; end
  def groove_outline(o)
    [[o[:x],o[:y]],[o[:x]+o[:w],o[:y]],[o[:x]+o[:w],o[:y]+o[:h]],[o[:x],o[:y]+o[:h]]]
  end
  def validate_job(job)
    all=parts(job); numbered=all.select { |p| p[:number] };raise 'Duplicate numbers' unless numbered.map { |p| p[:number] }.uniq.length==numbered.length
    all.each do |p|
      raise "Invalid size #{p[:id]}" unless [p[:w],p[:h],p[:t]].all? { |v| v>0 && v.finite? }
      p[:operations].each do |o|
        raise "Invalid machining depth: #{p[:id]}" unless o[:depth].finite? && o[:depth]>0
        if o[:face]=='EDGE'
          raise "Invalid edge bore: #{p[:id]}" unless o[:depth]<p[:w] && o[:diameter]<=p[:t] && o[:y]>=o[:diameter]/2 && o[:y]<=p[:h]-o[:diameter]/2
          next
        end
        raise "Depth exceeds thickness: #{p[:id]}" if o[:depth]>p[:t]
        if o[:kind]=='groove'
          raise "Invalid groove: #{p[:id]}" unless o[:w]>0 && o[:h]>0 && o[:depth]>0 && o[:depth]<p[:t]
          raise "Groove outside #{p[:id]}" unless groove_outline(o).all? { |point| S::Math3.inside?(point,p[:outline]) }
          next
        end
        16.times do |i|
          a=i*Math::PI/8
          point=[o[:x]+o[:diameter]/2*Math.cos(a),o[:y]+o[:diameter]/2*Math.sin(a)]
          # Rafix housing deliberately opens 0.5 mm into its mating edge.
          if o[:open_edge] && o[:recipe]=='review-rafix20-housing'
            point[0]=[[point[0],0].max,p[:w]].min
          end
          raise "Bore outside #{p[:id]} #{o[:recipe]}" unless S::Math3.inside?(point,p[:outline])
        end
      end
    end
    true
  end

  # Grain follows sheet X. Rotations affect outlines/holes, never labels.
  def nest(job)
    c=job[:settings]; sheets=[]
    panels(job).group_by { |p| [p[:material],p[:t]] }.sort_by { |k,_| k.join }.each do |(material,t),ps|
      group=[]
      ps.sort_by { |p| -p[:w]*p[:h] }.each do |p|
        rot=p[:grain]=='v' || (p[:h]>c[:sheet_h]-2*c[:margin] && p[:grain]=='none')
        w,h=rot ? [p[:h],p[:w]] : [p[:w],p[:h]]
        raise "Part #{p[:number]} exceeds sheet size" if w>c[:sheet_w]-2*c[:margin] || h>c[:sheet_h]-2*c[:margin]
        choice=nil
        group.each do |sheet|
          sheet[:rows].each { |row| choice=[sheet,row] if !choice && h<=row[:h] && row[:x]+w<=c[:sheet_w]-c[:margin] }
          unless choice
            y=sheet[:rows].empty? ? c[:margin] : sheet[:rows].last[:y]+sheet[:rows].last[:h]+c[:kerf]
            if y+h<=c[:sheet_h]-c[:margin]
              row={x:c[:margin],y:y,h:h}; sheet[:rows]<<row; choice=[sheet,row]
            end
          end
          break if choice
        end
        unless choice
          sheet={id:format('S%02d',sheets.length+1),material:material,t:t,w:c[:sheet_w],h:c[:sheet_h],placements:[],rows:[]}
          sheets<<sheet; group<<sheet; row={x:c[:margin],y:c[:margin],h:h};sheet[:rows]<<row;choice=[sheet,row]
        end
        sheet,row=choice
        sheet[:placements]<<{part:p[:number],x:row[:x],y:row[:y],w:w,h:h,rotated:rot}
        row[:x]+=w+c[:kerf]
      end
    end
    sheets.each { |s| s.delete(:rows) }; sheets
  end

  def place_xy(p,at,x,y)
    at[:rotated] ? [at[:x]+p[:h]-y,at[:y]+x] : [at[:x]+x,at[:y]+y]
  end
  def edge_segments(p,inset=0)
    # Only straight bounding edges receive bands. Gola notch returns stay unbanded.
    (p[:edges]||{}).flat_map do |edge,th|
      p[:outline].each_with_index.filter_map do |a,i|
        b=p[:outline][(i+1)%p[:outline].length]
        cond=case edge; when 'L' then a[0].abs<0.01 && b[0].abs<0.01; when 'R' then (a[0]-p[:w]).abs<0.01 && (b[0]-p[:w]).abs<0.01; when 'B' then a[1].abs<0.01 && b[1].abs<0.01; when 'T' then (a[1]-p[:h]).abs<0.01 && (b[1]-p[:h]).abs<0.01 end
        next unless cond
        dx,dy=case edge;when 'L' then [inset,0];when 'R' then [-inset,0];when 'B' then [0,inset];else [0,-inset];end
        [[a[0]+dx,a[1]+dy],[b[0]+dx,b[1]+dy],edge,th]
      end
    end
  end
end
