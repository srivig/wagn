format :html do
  def slot_options args
    @@slot_option_keys ||= Card::Chunk::Include.options.reject { |k| k == :view }.unshift :home_view
    options_hash = {}

    if @context_names.present?
      options_hash['name_context'] = @context_names.map( &:key ) * ','
    end

    @@slot_option_keys.inject(options_hash) do |hash, opt|
      hash[opt] = args[opt] if args[opt].present?
      hash
    end

    JSON( options_hash )
  end

  def wrap args = {}
    @slot_view = @current_view
    classes = [
      ( 'card-slot' unless args[:no_slot] ),
      "#{ @current_view }-view",
      ( args[:slot_class] if args[:slot_class] ),
      ( "STRUCTURE-#{args[:structure].to_name.key}" if args[:structure]),
      card.safe_set_keys
    ].compact

    div = %{<div id="#{card.cardname.url_key}" data-card-id="#{card.id}" data-card-name="#{h card.name}" style="#{h args[:style]}" class="#{classes*' '}" } +
      %{data-slot='#{html_escape_except_quotes slot_options( args )}'>#{ output yield }</div>}

    if params[:debug] == 'slot' && !tagged( @current_view, :no_wrap_comments )
      name = h card.name
      space = '  ' * @depth
      %{<!--\n\n#{ space }BEGIN SLOT: #{ name }\n\n-->#{ div }<!--\n\n#{space}END SLOT: #{ name }\n\n-->}
    else
      div
    end
  end

  def wrap_body args={}
    css_classes = [ 'card-body' ]
    css_classes << args[:body_class]                      if args[:body_class]
    css_classes += [ 'card-content', card.safe_set_keys ] if args[:content]
    content_tag :div, :class=>css_classes.compact*' ' do
      yield args
    end
  end

  def panel args={}
    wrap_with :div, :class=>"card-frame #{args[:panel_class]}" do
      output(yield)
    end
  end

  def frame args={}
    wrap args do
      [
        _optional_render( :menu, args ),
        panel(args) do
          [
            _optional_render( :header, args, :show),
            (%{ <div class="card-subheader">#{ args[:subheader] }</div> } if args[:subheader]),
            _optional_render( :help, args.merge(:help_class=>'alert alert-info'), :hide),
            (_render( :close_related_link, args) if @slot_view == :related),
            wrap_body(args) { output( yield args ) } ,
          ]
        end
      ]
    end
  end

  def frame_and_form action, args={}, form_opts={}
    form_opts.merge! args.delete(:form_opts) if args[:form_opts]
    form_opts[:hidden] = args.delete(:hidden)
    frame args do
      card_form action, form_opts do
        output( yield args )
      end
    end
  end


  # alert_types: 'success', 'info', 'warning', 'danger'
  def alert alert_type, args={}
    css_class = "alert alert-#{alert_type} "
    css_class += 'alert-dismissible ' if args[:dismissible]
    css_class += args[:alert_class] if args[:alert_class]
    close_button = args[:dismissible] ? %{
        <button type="button" class="close" data-dismiss="alert" aria-label="Close">
          <span aria-hidden="true">&times;</span>
        </button>
      } : ''
    content_tag :div, :class=>css_class, :role=>'alert' do
      close_button + output( yield args)
    end
  end

  def wrap_main(content)
    return content if Env.ajax? || params[:layout]=='none'
    %{<div id="main">#{content}</div>}
  end

  def wrap_with tag, content_or_args={}, html_args={}
    if block_given?
      content_tag( tag, content_or_args ) do
        output( yield ).html_safe
      end
    else
      content_tag( tag, html_args ) do
        output( content_or_args ).html_safe
      end
    end
  end

  def wrap_each_with tag, content_or_args={}, args={}
    content = block_given? ? yield(args) : content_or_args
    args    = block_given? ? content_or_args : args
    content.compact.map do |item|
      wrap_with tag, args do
        item
      end
    end.join "\n"
  end

  view :close_related_link do |args|
    card_link( args[:parent], :text=>glyphicon('remove'), :view=>:home, :remote=>true, :class=>'pull-right slotter close-related-view', :title=>'cancel', 'data-slot-selector'=>'.card-slot.related-view')
  end

end
