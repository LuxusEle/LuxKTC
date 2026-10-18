# frozen_string_literal: true
module AJBoardKitchen
  module Layout
    extend self
    remove_const(:BASE) if const_defined?(:BASE,false)
    BASE=[['B01','tall_pantry',450,2100,580],['B02','tall_oven_micro',600,2100,580],['B03','base_sink',600,720,560],['B04','base_gola',450,720,560],['B05','base_gola',600,720,560],['B06','base_single',300,720,560]].freeze
    remove_const(:UPPER) if const_defined?(:UPPER,false)
    UPPER=[['W01','wall_double','B03'],['W02','wall_single','B04'],['W03','wall_hood','B05'],['W04','wall_open','B06']].freeze
    def overrides(c,id); c.fetch(:cabinet_overrides,{}).fetch(id,{}); end
    def specs(c)
      x=24.0
      base=BASE.map do |id,type,w,h,d|
        o=overrides(c,id);w=o.fetch(:w,w).to_f;h=o.fetch(:h,h).to_f;d=o.fetch(:d,d).to_f
        row={id:id,type:type,w:w,h:h,d:d,x:x,z:0.0,locked:o.fetch(:locked,%w[B02 B03 B05].include?(id)),options:o}
        x+=w;row
      end
      upper=UPPER.map do |id,type,anchor|
        b=base.find { |r| r[:id]==anchor };o=overrides(c,id)
        # Widths follow the matching lower unit. Editing an upper width edits its
        # anchor explicitly in the preview, keeping the hood over the hob.
        {id:id,type:type,w:b[:w],h:o.fetch(:h,600).to_f,d:o.fetch(:d,330).to_f,x:b[:x],z:1600.0,anchor:anchor,locked:b[:locked],options:o}
      end
      (base+upper).each { |r| validate_spec(r,c) }
      heights=base.reject { |r| %w[B01 B02].include?(r[:id]) }.map { |r| r[:h] }.uniq
      raise 'Base cupboards under the shared worktop must have one height.' unless heights.size==1
      [base,upper]
    end
    def width_bounds(id)
      case id
      when 'B02','B05' then [600.0,600.0]
      when 'B03' then [550.0,900.0]
      when 'B01' then [300.0,750.0]
      else [250.0,900.0]
      end
    end
    def validate_spec(r,c)
      raise "Invalid dimensions for #{r[:id]}" unless r.values_at(:w,:h,:d).all? { |n| n.finite? }
      bounds=width_bounds(r[:anchor]||r[:id])
      raise "#{r[:id]} width must be #{bounds.join(' to ')} mm (appliance limits)." unless r[:w].between?(*bounds)
      tall=%w[B01 B02].include?(r[:id]);wall=!!r[:anchor]
      hr=wall ? [400,900] : tall ? [1900,2300] : [650,850]
      dr=wall ? [300,450] : [560,650]
      raise "#{r[:id]} height must be #{hr.join(' to ')} mm." unless r[:h].between?(*hr)
      raise "#{r[:id]} depth must be #{dr.join(' to ')} mm." unless r[:d].between?(*dr)
    end
    def edit(config,id,changes,fill:'both')
      c=AJBoardKitchen.settings(config);base,upper=specs(c)
      selected=(base+upper).find { |r| r[:id]==id }
      raise 'Select an AJ cabinet.' unless selected
      raise 'Choose left, right, both, or extend run.' unless %w[left right both extend].include?(fill)
      changes=changes.transform_keys(&:to_sym)
      allowed=%i[w h d joinery hinge edge front_edge locked]
      raise 'Unsupported cabinet option.' unless (changes.keys-allowed).empty?
      target=selected[:anchor]||id
      row=base.find { |r| r[:id]==target }
      fresh=Marshal.load(Marshal.dump(c));os=fresh[:cabinet_overrides]
      os[id]||={}
      changes.each do |k,v|
        next if k==:w || (k==:locked && selected[:anchor])
        v=='inherit' ? os[id].delete(k) : os[id][k]=v
      end
      os[target]||={}
      os[target][:locked]=changes[:locked] if changes.key?(:locked)
      width=Float(changes.fetch(:w,selected[:w]));delta=width-row[:w]
      os[target][:w]=width
      # Shared worktop: resizing one base height raises/lowers all four base boxes.
      if changes.key?(:h) && %w[B03 B04 B05 B06].include?(id)
        %w[B03 B04 B05 B06].each { |bid| (os[bid]||={})[:h]=Float(changes[:h]) }
      end
      if delta.abs>0.001 && fill!='extend'
        at=base.index(row)
        candidates=base.each_with_index.select { |r,i| r[:id]!=target && !r[:locked] && (fill=='both' || (fill=='left' ? i<at : i>at)) }.map(&:first)
        remaining=-delta
        # Equal change, with bounds: any saturated neighbor drops out of the pool.
        widths=candidates.to_h { |r| [r[:id],r[:w]] }
        pool=candidates.dup
        until remaining.abs<0.00001 || pool.empty?
          share=remaining/pool.size
          pool.dup.each do |r|
            lo,hi=width_bounds(r[:id]);before=widths[r[:id]]
            after=[[before+share,lo].max,hi].min
            widths[r[:id]]=after;remaining-=after-before
            pool.delete(r) if after<=lo+0.00001 || after>=hi-0.00001
          end
        end
        raise 'Not enough unlocked width on that side. Choose another fill direction or Extend run.' if remaining.abs>0.001
        widths.each { |bid,w| (os[bid]||={})[:w]=w }
      end
      fresh=AJBoardKitchen.settings(fresh)
      specs(fresh)
      fresh
    end
  end
end
