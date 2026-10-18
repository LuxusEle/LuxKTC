# frozen_string_literal: true
module AJBoardKitchen
  class CabinetPickTool
    def activate
      Sketchup.status_text='AJ: click a cabinet to edit its dimensions and assembly options. Esc cancels.'
    end
    def onLButtonDown(_flags,x,y,view)
      AJBoardKitchen.guard do
        picker=view.pick_helper;picker.do_pick(x,y)
        id=nil
        picker.count.times do |i|
          path=picker.path_at(i)||[]
          next unless path.any? { |e| e.respond_to?(:get_attribute) && e.get_attribute(DICT,'owned') }
          id=AJBoardKitchen.cabinet_id_from(path)
          break if id
        end
        if id
          Sketchup.active_model.select_tool(nil)
          AJBoardKitchen.edit_cabinet(id)
        else
          Sketchup.status_text='Click an AJ cabinet, rather than a nested sheet or worktop.'
        end
      end
    end
    def onCancel(_reason,_view); Sketchup.active_model.select_tool(nil); end
  end

  def cabinet_id_from(entities)
    entities.to_a.reverse_each do |e|
      next unless e.respond_to?(:get_attribute)
      raw=e.get_attribute(S::DICT,'cabinet')||e.get_attribute(S::DICT,'part')
      next unless raw
      data=JSON.parse(raw);id=data['cabinet_id']||data['id']
      return id if id && id.match?(/\A[BW]\d\d\z/)
    end
    nil
  end
  def pick_cabinet
    active!
    id=cabinet_id_from((Sketchup.active_model.active_path||[])+Sketchup.active_model.selection.to_a)
    id ? edit_cabinet(id) : Sketchup.active_model.select_tool(CabinetPickTool.new)
  end
  def edit_cabinet(id)
    active!;@editing_id=id;show_dialog;sync_dialog
  end
  def preview_cabinet_edit(payload)
    active!;@pending_edit=nil
    input=payload.transform_keys(&:to_sym);id=input.fetch(:id)
    config=Layout.edit(@config,id,input.fetch(:changes),fill:input.fetch(:fill,'both'))
    candidate=make_job(config);sheets=nest(candidate)
    diffs=candidate[:cabinets].reject { |c| c[:id]=='R01' }.filter_map do |c|
      old=@job[:cabinets].find { |x| x[:id]==c[:id] }
      fields=%i[w h d].filter_map { |k| "#{k.to_s.upcase} #{old[k].round(2)} -> #{c[k].round(2)}" if (old[k]-c[k]).abs>0.001 }
      fields << "X #{old[:pose][0].round(2)} -> #{c[:pose][0].round(2)}" if (old[:pose][0]-c[:pose][0]).abs>0.001
      %i[joinery hinge edge front_edge].each do |k|
        a=old[:options][:config][k];b=c[:options][:config][k]
        fields << "#{k}: #{a} -> #{b}" if a!=b
      end
      fields << "width lock: #{c[:width_locked]}" if old[:width_locked]!=c[:width_locked]
      "#{c[:id]}: #{fields.join(', ')}" unless fields.empty?
    end
    diffs << "Run: #{candidate[:width].round(2)} mm. #{sheets.size} sheets. Apply rebuilds parts, drilling, labels and nesting."
    diffs.unshift("Upper width follows #{candidate[:cabinets].find { |c| c[:id]==id }[:width_anchor]}; its lower unit and neighbors are included.") if id.start_with?('W')
    @pending_edit={config:config,root:@view.root,job:@job}
    @dialog.execute_script("showEditPreview(#{JSON.generate(diffs.join("\n"))})")
  end
  def apply_cabinet_edit
    active!;pending=@pending_edit
    raise 'Preview the cabinet changes first.' unless pending && pending[:root]==@view.root && pending[:job].equal?(@job)
    build!(pending[:config],preserve_camera:true)
    @pending_edit=nil
    update_status('Cabinet changes applied. Drilling, labels, worktop and nesting rebuilt.')
  end
  def renest!(input={})
    active!
    conf=settings(@config.merge(input.transform_keys(&:to_sym).slice(:sheet_w,:sheet_h,:kerf,:margin)))
    candidate=@job.merge(settings:conf)
    nest(candidate) # Reject impossible sheets before touching the model.
    @view.renest!(candidate);@job=candidate;@config=conf;@pending_edit=nil
    sync_dialog;@view.focus_nesting;update_status('Nesting regenerated from the current parts and machining.')
  end

  class View
    def renest!(job)
      started=false
      raise 'Exit component editing before re-nesting.' unless @model.active_path.nil?
      old=@nest_root;old_job=@job
      others=@model.entities.to_a.reject { |e| e==@root }
      maxx=others.filter_map { |e| e.bounds.max.x.to_f*25.4 if e.respond_to?(:bounds) && !e.bounds.empty? }.max||0
      offset=@root.transformation.origin.x.to_f*25.4
      start=[maxx,offset+job[:width]].max+1000-offset
      @model.start_operation('AJ re-nest current cabinet parts',true)
      started=true
      @job=job;draw_nesting(start)
      old.erase! if old && old.valid?
      @root.set_attribute(DICT,'job',JSON.generate(job))
      @model.commit_operation
    rescue StandardError
      @model.abort_operation if started
      @job=old_job if old_job;@nest_root=old if old;raise
    end
  end
end
