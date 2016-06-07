format :html do
  ###---( TOP_LEVEL (used by menu) NEW / EDIT VIEWS )

  view :new, :perms=>:create, :tags=>:unknown_ok do |args|
    frame_and_form :create, args, 'main-success'=>'REDIRECT' do
      [
        _optional_render( :name_formgroup,     args ),
        _optional_render( :type_formgroup,     args ),
        _optional_render( :content_formgroup, args ),
        _optional_render( :button_formgroup,   args )
      ]
    end
  end


  def default_new_args args
    hidden = args[:hidden] ||= {}
    hidden[:success] ||= card.rule(:thanks) || '_self'
    hidden[:card   ] ||={}

    args[:optional_help] ||= :show

    # name field / title
    if !params[:name_prompt] and !card.cardname.blank?
      # name is ready and will show up in title
      hidden[:card][:name] ||= card.name
    else
      # name is not ready; need generic title
      args[:title] ||= "New #{ card.type_name unless card.type_id == Card.default_type_id }" #fixme - overrides nest args
      unless card.rule_card :autoname
        # prompt for name
        hidden[:name_prompt] = true unless hidden.has_key? :name_prompt
        args[:optional_name_formgroup] ||= :show
      end
    end
    args[:optional_name_formgroup] ||= :hide


    # type field
    if ( !params[:type] and !args[:type] and
        ( main? || card.simple? || card.is_template? ) and
        Card.new( :type_id=>card.type_id ).ok? :create #otherwise current type won't be on menu
      )
      args[:optional_type_formgroup] = :show
    else
      hidden[:card][:type_id] ||= card.type_id
      args[:optional_type_formgroup] = :hide
    end


    cancel = if main?
      { :class=>'redirecter', :href=>Card.path_setting('/*previous') }
    else
      { :class=>'slotter',    :href=>path( :view=>:missing         ) }
    end

    args[:buttons] ||= %{
      #{ button_tag 'Submit', :class=>'create-submit-button', :disable_with=>'Submitting', :situation=>'primary' }
      #{ button_tag 'Cancel', :type=>'button', :class=>"create-cancel-button #{cancel[:class]}", :href=>cancel[:href] }
    }

  end



  view :edit, :perms=>:update, :tags=>:unknown_ok do |args|
    frame_and_form :update, args do
      [
        _optional_render( :content_formgroup, args ),
        _optional_render( :button_formgroup,   args )
      ]
    end
  end


  def default_edit_args args
    args[:optional_help] ||= :show
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit

    args[:buttons] ||= %{
      #{ button_tag 'Submit', :class=>'submit-button', :disable_with=>'Submitting', :situation=>'primary' }
      #{ button_tag 'Cancel', :class=>'cancel-button slotter', 'data-slot-selector'=>args[:cancel_slot_selector],
       :href=>(args[:cancel_path] || path), :type=>'button' }
    }
  end


  view :edit_name, :perms=>:update do |args|
    frame_and_form( { :action=>:update, :id=>card.id }, args, 'main-success'=>'REDIRECT' ) do
      [
        _render_name_formgroup( args ),
        _optional_render( :confirm_rename, args ),
        _optional_render( :button_formgroup, args )
      ]
    end
  end


  view :confirm_rename do |args|
    referers = args[:referers]
    dependents = card.dependents
    alert 'warning' do
      %{
        <h5>Are you sure you want to rename <em>#{card.name}</em>?</h5>
        #{ %{ <h6>This change will...</h6> } if referers.any? || dependents.any? }
        <ul>
          #{ %{<li>automatically alter #{ dependents.size } related name(s). </li>} if dependents.any? }
          #{ %{<li>affect at least #{referers.size} reference(s) to "#{card.name}".</li>} if referers.any? }
        </ul>
        #{ %{<p>You may choose to <em>update or ignore</em> the references.</p>} if referers.any? }
      }
    end
  end


  def default_edit_name_args args
    referers = args[:referers] = card.extended_referencers
    args[:hidden] ||= {}
    args[:hidden].reverse_merge!(
      :success  => '_self',
      :old_name => card.name,
      :referers => referers.size,
      :card     => { :update_referencers => false }
    )
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit_name
    args[:buttons] = %{
      #{ button_tag 'Rename and Update', :disable_with=>'Renaming', :class=>'renamer-updater', :situation=>'primary' }
      #{ button_tag 'Rename',            :disable_with=>'Renaming', :class=>'renamer'         }
      #{ button_tag 'Cancel', :class=>'slotter',  :type=>'button', :href=>path }
    }

  end


  view :edit_type, :perms=>:update do |args|
    frame_and_form :update, args do
    #'main-success'=>'REDIRECT: _self', # adding this back in would make main cards redirect on cardtype changes
      [
        _render_type_formgroup( args ),
        optional_render( :button_formgroup, args )
      ]
    end
  end

  def default_edit_type_args args
    args[:variety] = :edit #YUCK!
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit_type
    args[:hidden] ||= { :success=>{:view=>:edit} }
    args[:buttons] = %{
      #{ button_tag 'Submit', :disable_with=>'Submitting', :situation=>'primary' }
      #{ button_tag 'Cancel', :href=>path(:view=>:edit), :type=>'button', :class=>'slotter' }
    }
  end

  view :edit_rules, :tags=>:unknown_ok do |args|
    frame args do
      subformat( current_set_card ).render_content args
    end
  end

  def default_edit_rules_args args
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit_rules
  end

  view :options, {:view=>:edit_rules, :mod=>All::RichHtml::Editing::HtmlFormat} # for backwards compatibility


  view :edit_structure do |args|
    slot_args = {:cancel_slot_selector=>'.card-slot.related-view', :cancel_path=>card.format.path(:view=>:edit), :optional_edit_toolbar=>:hide, :hidden=>{:success=>"REDIRECT: #{card.structure.key}"}}
    render_related args.merge(:related=>{:card=>card.structure, :view=>:edit, :slot=>slot_args})
    # frame args do
    #   nest card.structure, slot_args.merge(:view=>:edit)
    # end
  end

  def default_edit_structure_args args
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit_structure
  end

  view :edit_nests do |args|
    #nests = card.fetch(:trait=>:includes)
    includes = Card::Content.new(card.content, card).find_chunks( Card::Chunk::Include )

    frame args do
      includes.map do |chunk|
        if chunk.referee_card
          nest chunk.referee_card, :view=>:edit_rules, :hide=>'set_label'
        end
      end
      #nest nests, :view=>:content, :items=>{:view=>:edit_rules, :hide=>'set_label'}
    end
  end

  def default_edit_nests_args args
    args[:optional_edit_toolbar] ||= :show
    args[:active_toolbar_view] ||= :edit_nests
  end
end



