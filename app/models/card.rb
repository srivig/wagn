
class Card < ActiveRecord::Base
end
require 'wiki_reference'
require 'wagn/card/model'

class Card
  def destroy!
    # FIXME: do we want to overide confirmation by setting confirm_destroy=true here?
    # This is aliased in Permissions, which could be related to the above comment
    self.confirm_destroy = true
    destroy or raise Wagn::Oops, "Destroy failed: #{errors.full_messages.join(',')}"
  end
  include Wagn::Card::Model

  #
  # == Associations
  #  
  # Given cards A, B and A+B     
  # 
  # trunk::  from the point of f of A+B,  A is the trunk  
  # tag::  from the point of view of A+B,  B is the tag
  # left_junctions:: from the point of view of B, A+B is a left_junction (the A+ part is on the left)  
  # right_junctions:: from the point of view of A, A+B is a right_junction (the +B part is on the right)  
  #
  set_table_name 'cards'
                                         
  # FIXME:  this is ugly, but also useful sometimes... do in a more thoughtful way maybe?
  cattr_accessor :debug    
  Card.debug = false

  cattr_accessor :cache  
  def self.cache() @@cache || Wagn::Cache.new(Rails.cache) end
#  self.cache = {}

=begin
  [:before_validation, :before_validation_on_create, :after_validation, 
    :after_validation_on_create, :before_save, :before_create, :after_save,
    :after_create,
  ].each do |callback|
    self.send(callback) do 
      Rails.logger.debug "Card#callback #{callback}"
    end
  end
=end   
   
  belongs_to :trunk, :class_name=>'Card', :foreign_key=>'trunk_id' #, :dependent=>:dependent
  has_many   :right_junctions, :class_name=>'Card', :foreign_key=>'trunk_id'#, :dependent=>:destroy  

  belongs_to :tag, :class_name=>'Card', :foreign_key=>'tag_id' #, :dependent=>:destroy
  has_many   :left_junctions, :class_name=>'Card', :foreign_key=>'tag_id'  #, :dependent=>:destroy
    
  belongs_to :current_revision, :class_name => 'Revision', :foreign_key=>'current_revision_id'
  has_many   :revisions, :order => 'id', :foreign_key=>'card_id'

  belongs_to :extension, :polymorphic=>true

  belongs_to :updater, :class_name=>'::User', :foreign_key=>'updated_by'

  has_many :permissions, :foreign_key=>'card_id' #, :dependent=>:delete_all

  before_destroy :destroy_extension
               
  #before_validation_on_create :set_needed_defaults
    
  attr_accessor :comment, :comment_author, :confirm_rename, :confirm_destroy,
    :from_trash, :update_referencers, :allow_typecode_change, :virtual,
  :skip_defaults, :loaded_trunk, :blank_revision, :broken_cardtype

  # setup hooks on AR callbacks
  # Note: :after_create is called from end of set_initial_content now
  [:before_save, :before_create, :after_save ].each do |hookname| 
    self.send( hookname ) do |card|
      Wagn::Hook.call hookname, card
    end
  end
    
  # apparently callbacks defined this way are called last.
  # that's what we want for this one.  
  def after_save 
    if self.typecode == 'Cardtype'
      Rails.logger.debug "Cardtype after_save resetting"
      ::Cardtype.reset_cache
    end
#      Rails.logger.debug "Card#after_save end"
    update_attachment
    true
  end
      
  def update_attachment # the module definition overrides this for card_attachements
  end

  private
    belongs_to :reader, :polymorphic=>true  
    
    def log(msg)
      ActiveRecord::Base.logger.info(msg)
    end
    
    def on_type_change
    end  
    
  public
      
  
  def set_defaults args
    #Rails.logger.debug "Card(#{name})#set_defaults"
    # autoname
    if args["name"].blank?
      ::User.as(:wagbot) do
        if ac = setting_card('autoname') and autoname_card = ac.card
          self.name = autoname_card.content
          autoname_card.content = autoname_card.content.next  #fixme, should give placeholder on new, do next and save on create
          autoname_card.save!
        end                                         
      end
    end
    
    
    if !args['permissions']
    # The following are only necessary for setting permissions.  Should remove once we have set/setting -based perms
      if name and name.junction? and name.valid_cardname? 
        self.trunk ||= Card.fetch_or_new name.left_name, {:skip_virtual=>true}
        self.tag   ||= Card.fetch_or_new name.tag_name,    {:skip_virtual=>true}
      end
    
      self.set_default_permissions 
    end

    #default content
    ::User.as(:wagbot) do
      if !args['content'] and self.content.blank? and default_card = setting_card('default')
        self.content = default_card.content
      end
    end
    

    # misc defaults- trash, key, fallbacks
    self.key = name.to_key if name
    self.name='' if name.nil?
    self
  end
  
  def set_default_permissions
    source_card = setting_card('content', 'default')  #not sure why "template" doesn't work here.
    if source_card
      perms = source_card.card.permissions.reject { 
        |p| p.task == 'create' unless (typecode=='Cardtype' or template?) 
      }
    else
      #raise( "Missing permission configuration for #{name}" ) unless source_card && !source_card.permissions.empty?
      perms = [:read,:edit,:delete].map{|t| ::Permission.new(:task=>t.to_s, :party=>::Role[:auth])}
    end
  
    # We loop through and create copies of each permission object here because
    # direct copies end up re-assigning which card the permission objects are assigned to.
    # leads to painful errors.
    self.permissions = perms.map do |p|  
      if p.task == 'read'
        party = p.party
        
        if trunk and tag
          trunk_reader = (trunk.who_can(:read) || (trunk.set_default_permissions && trunk.who_can(:read)))
          tag_reader   = (  tag.who_can(:read) || (  tag.set_default_permissions &&   tag.who_can(:read)))
          #Rails.logger.debug "trunk = #{trunk.inspect} ....... who can read = #{trunk.who_can(:read)}"
          #Rails.logger.debug "tag = #{tag.inspect} ....... who can read = #{tag.who_can(:read)}"
          trunk_reader && tag_reader || raise("bum permissions: #{trunk.name}:#{trunk_reader}, #{tag.name}:#{tag_reader}")

          tag_override = (trunk_reader.anonymous? || (authenticated?(trunk_reader) && !tag_reader.anonymous?))
          party = (tag_override ? tag_reader : trunk_reader)
        end
        Permission.new :task=>p.task, :party=>party
      else
        Permission.new :task=>p.task, :party_id=>p.party_id, :party_type=>p.party_type
      end
    end
  end
  
  def card
    Rails.logger.info "DEPRECATED: no need to do .card, use self #{Kernel.caller[0..4]*"\n"}"
    self
  end
  
  # Creation & Destruction --------------------------------------------------
  #alias_method :ar_new, :new

  def initialize(args={})
    args = {} if args.nil?
    args = args.stringify_keys
    args['trash'] = false
      
    Rails.logger.debug "Card.initialize #{args.inspect}"
    args['typecode'] ||= case
    when type_name = args.delete('type');  ::Cardtype.classname_for(type_name)
    when args.delete('skip_type_lookup');  'Basic'
    when args['name']                   ;  nil  #lookup after super
    else                                ;  'Basic'
    end 

    att_id = args.delete('attachment_id')

    super

    @loaded_trunk = args['loaded_trunk'] if args['loaded_trunk']
    
    self.typecode ||= template.typecode
    fail "NO TYPECODE" unless self.typecode
    Rails.logger.debug "Card.initialize #{typecode.inspect} #{args.inspect}"
    include_singleton_modules

    self.attachment_id = att_id if att_id # now that we have modules, we have this field
      
    yield(new_card) if block_given?
    set_defaults( args ) unless args['skip_defaults'] 
  end 

  def after_find
    include_singleton_modules
  end
  
  def include_singleton_modules
    return unless typecode
    singleton = class << self; self end
    singleton.include_type_module(typecode)
  end

  class << self
    def include_type_module(typecode)
      #mod = Card.const_get(typecode) 
      con = (mod=Card.const_get(typecode.to_sym)).to_s.split('::')
      Rails.logger.debug "include_type_module(#{typecode}) #{con.inspect}, #{mod.inspect}"
      return if con.length != 2 or con[0] != 'Card'
      Rails.logger.debug "include_type_module(#{typecode}) #{mod.inspect}"
      include mod if mod
    rescue Exception=>e
      return unless mod
      warn "Error including module (#{typecode}, #{mod.inspect}) #{e} #{e.backtrace[0..3]*"\n"}"
      nil
    end
    
    def find_or_create!(args={})
      find_or_create(args) || raise(ActiveRecord::RecordNotSaved)
    end
    
    def find_or_create(args={})
      raise "find or create must have name" unless args[:name]
      Card.fetch_or_create(args[:name], {}, args)
    end
    
    def find_or_new(args={})
      raise "find_or_new must have name" unless args[:name]
      Card.fetch_or_new(args[:name], {}, args)
    end
                        
  end

  def save_with_trash!
    save || raise(errors.full_messages.join('. '))
  end
  alias_method_chain :save!, :trash

  def save_with_trash(perform_checking=true)
    pull_from_trash if new_record?
    save_without_trash(perform_checking)
  end
  alias_method_chain :save, :trash   

  def reset_cardtype_cache() end

  def pull_from_trash
    return unless key
    return unless trashed_card = Card.find_by_key_and_trash(key, true) 
    #could optimize to use fetch if we add :include_trashed_cards or something.  
    #likely low ROI, but would be nice to have interface to retrieve cards from trash...
    self.id = trashed_card.id
    self.from_trash = self.confirm_rename = true
    @new_record = false
    self.before_validation_on_create
  end
  

  def multi_create(cards)
    Wagn::Hook.call :before_multi_create, self, cards
    multi_save(cards)
    Rails.logger.info "Card#callback after_multi_create"
    Wagn::Hook.call :after_multi_create, self
  end
  
  def multi_update(cards)
    Wagn::Hook.call :before_multi_update, self, cards
    multi_save(cards)
    Rails.logger.info "Card#callback after_multi_update"
    Wagn::Hook.call :after_multi_update, self
  end
  
  def multi_save(cards)
    Wagn::Hook.call :before_multi_save, self, cards
    cards.each_pair do |name, opts|
      opts[:content] ||= ""
      # make sure blank content doesn't override first assignments if they are present
      #if (opts['first'].present? or opts['items'].present?) 
      #  opts.delete('content')
      #end                                                                               
      name = name.post_cgi.to_absolute(self.name)
      logger.info "multi update working on #{name}: #{opts.inspect}"
      if card = Card.fetch(name, :skip_virtual=>true)
        card.update_attributes(opts)
      elsif opts[:content].present? and opts[:content].strip.present?
        opts[:name] = name                
        if ::Cardtype.create_ok?( self.typecode ) && !::Cardtype.create_ok?( Card.new(opts).typecode )
          ::User.as(:wagbot) { Card.create(opts) }
        else
          Card.create(opts)
        end
      end
      if card and !card.errors.empty?
        card.errors.each do |field, err|
          self.errors.add card.name, err
        end
      end
    end  
    Rails.logger.info "Card#callback after_multi_save"
    Wagn::Hook.call :after_multi_save, self, cards
  end

  def new_card?
    new_record? || from_trash
  end

  def destroy_with_trash(caller="")     
    if callback(:before_destroy) == false
      errors.add(:destroy, "could not prepare card for destruction")
      return false 
    end  
    deps = self.dependents
    self.update_attribute(:trash, true) 
    deps.each do |dep|
      next if dep.trash
      dep.confirm_destroy = true
      dep.destroy_with_trash("#{caller} -> #{name}")
    end

    callback(:after_destroy) 
    true
  end
  alias_method_chain :destroy, :trash
          
  def destroy_with_validation
    errors.clear 
    
    validate_destroy
    
    if !dependents.empty? && !confirm_destroy
      errors.add(:confirmation_required, "because #{name} has #{dependents.size} dependents")
    end
    
    dependents.each do |dep|    
      dep.send :validate_destroy
      if dep.errors.on(:destroy)  
        errors.add(:destroy, "can't destroy dependent card #{dep.name}: #{dep.errors.on(:destroy)}")
      end
    end

    if errors.empty?
      destroy_without_validation
    else
      return false
    end
  end
  alias_method_chain :destroy, :validation
  

   
  # Extended associations ----------------------------------------


  def left
    Card.fetch name.trunk_name, :skip_virtual=> true
  end
  def right
    Card.fetch name.tag_name,   :skip_virtual=> true
  end
  
  def cardtype_name()
    #raise "No type: #{self.inspect}" unless self.typecode
    typecode or return 'Basic'
    #Rails.logger.info "No cardtype: #{self}, #{Kernel.caller*"\n"}" unless typecode
    ::Cardtype.name_for( typecode )
  end
  
  
  def pieces
    simple? ? [self] : ([self] + trunk.pieces + tag.pieces).uniq 
  end
  
  def particles
    name.particle_names.map{|name| Card[name]} ##FIXME -- inefficient (though scarcely used...)    
  end

  def junctions(args={})
    return [] if new_record? #because lookup is done by id, and the new_records don't have ids yet.  so no point.  
    args[:conditions] = ["trash=?", false] unless args.has_key?(:conditions)
    args[:order] = 'id' unless args.has_key?(:order)    
    # aparently find f***s up your args. if you don't clone them, the next find is busted.
    left_junctions.find(:all, args.clone) + right_junctions.find(:all, args.clone)
  end

  def dependents(*args) 
    return [] if new_record? #because lookup is done by id, and the new_records don't have ids yet.  so no point. 
    junctions(*args).map { |r| [r ] + r.dependents(*args) }.flatten 
  end

  def extended_referencers
    (dependents + [self]).plot(:referencers).flatten.uniq
  end

  def card  ## is this still necessary or just legacy from CachedCards?
    self
  end
  
  def type_card
    ct = ::Cardtype.find_by_class_name( self.typecode )
    raise("Error in #{self.name}: No cardtype for #{self.typecode}")  unless ct
    ct.card
  end

  def drafts
    revisions.find(:all, :conditions=>["id > ?", current_revision_id])
  end
         
  def save_draft( content )
    clear_drafts
    revisions.create(:content=>content)
  end

  def previous_revision(revision)
    revision_index = revisions.each_with_index do |rev, index| 
      if rev.id == revision.id 
        break index 
      else
        nil
      end
    end
    if revision_index.nil? or revision_index == 0
      nil
    else
      revisions[revision_index - 1]
    end
  end
  
  # I don't really like this.. 
  #def attribute_card( attr_name )
  #  ::User.as :wagbot do
  #    Card.fetch( name + JOINT + attr_name , :skip_virtual => true)
  #  end
  #end
   
  def revised_at
    if cached_revision && rtime = cached_revision.updated_at
      rtime
    else
      Time.now
    end
  end

  # Dynamic Attributes ------------------------------------------------------        
  def skip_defaults?
    # when Calling Card.new don't set defaults.  this is for performance reasons when loading
    # missing cards. 
    !!skip_defaults  ##ok.  but this line is bizarre.
  end

  def known?
    !(new_card? && !virtual?)
  end
  
  def virtual?
    @virtual
  end    
  
  def content   
    new_card? ? ok!(:create_me) : ok!(:read)
    cached_revision.new_record? ? "" : cached_revision.content
  end   
  
  def cached_revision
    #return current_revision || get_blank_revision
    
    case
    when (@cached_revision and @cached_revision.id==current_revision_id); 
    when (@cached_revision=Card.cache.read("#{key}-content") and @cached_revision.id==current_revision_id);
    else
      @cached_revision = current_revision || get_blank_revision
      Card.cache.write("#{key}-content", @cached_revision)
    end
    @cached_revision
  end
  
  def get_blank_revision
    @blank_revision ||= Revision.new
  end
  
  def raw_content
    templated_content || content
  end

  def typecode
    @typecode ||= read_attribute :typecode
  end

  def codename
    return nil unless extension and extension.respond_to?(:codename)
    extension.codename
  end

  def class_name
    raise "class_name is Deprecated. use cardtype instead"
  end
  
  def name_from_parts
    simple? ? name : (trunk.name_from_parts + '+' + tag.name_from_parts)
  end

  def simple?() 
    name.simple? 
  end
  
  def junction?() !simple? end
     
  def authenticated?(party)
    party==::Role[:auth]
  end

  def to_s
    "#<#{self.class.name}:#{self.attributes['name']}>"
  end

  def mocha_inspect
    to_s
  end

  def repair_key
    ::User.as :wagbot do
      correct_key = name.to_key
      current_key = key
      return self if current_key==correct_key

      saved =   ( self.key  = correct_key and self.save! )
      saved ||= ( self.name = current_key and self.save! )

      saved ? self.dependents.each { |c| c.repair_key } : self.name = "BROKEN KEY: #{name}"
      self
    end
  rescue
    self
  end



   
 protected
  def clear_drafts
    connection.execute(%{
      delete from revisions where card_id=#{id} and id > #{current_revision_id} 
    })
  end

  
=begin
  def clone_to_type( newtype )
    attrs = self.attributes_before_type_cast
    attrs['type'] = newtype 
    Card.class_for(newtype, :codename).new do |record|
      record.send :instance_variable_set, '@attributes', attrs
      record.send :instance_variable_set, '@new_record', false
      # FIXME: I don't really understand why it's running the validations on the new card?
      record.allow_type_change = allow_type_change
    end
  end
  
  def copy_errors_from( card )
    card.errors.each do |attr, err|
      self.errors.add attr, err
    end
  end
=end
  
  # Because of the way it chains methods, 'tracks' needs to come after
  # all the basic method definitions, and validations have to come after
  # that because they depend on some of the tracking methods.
  tracks :name, :content, :typecode, :comment, :permissions#, :reader, :writer, :appender

  def name_with_key_sync=(name)
    name ||= ""
    self.key = name.to_key
    self.name_without_key_sync = name
  end
  alias_method_chain :name=, :key_sync
    

  validates_presence_of :name
  validates_associated :extension #1/2 ans:  this one runs the user validations on user cards. 


  validates_each :name do |rec, attr, value|
    if rec.updates.for?(:name)
      rec.errors.add :name, "may not contain any of the following characters: #{String::CARDNAME_BANNED_CHARACTERS[1..-1].join ' '} " unless value.valid_cardname?
      # this is to protect against using a junction card as a tag-- although it is technically possible now.
      rec.errors.add :name, "#{value} in use as a tag" if (value.junction? and rec.simple? and rec.left_junctions.size>0)

      # validate uniqueness of name
      condition_sql = "cards.key = ? and trash=?"
      condition_params = [ value.to_key, false ]   
      unless rec.new_record?
        condition_sql << " AND cards.id <> ?" 
        condition_params << rec.id
      end
      if c = Card.find(:first, :conditions=>[condition_sql, *condition_params])
        rec.errors.add :name, "must be unique-- A card named '#{c.name}' already exists"
      end
      
      # require confirmation for renaming multiple cards
      if !rec.confirm_rename 
        if !rec.dependents.empty? 
          rec.errors.add :confirmation_required, "#{rec.name} has #{rec.dependents.size} dependents"
        end
      
        if rec.update_referencers.nil? and !rec.extended_referencers.empty? 
          rec.errors.add :confirmation_required, "#{rec.name} has #{rec.extended_referencers.size} referencers"
        end
      end
    end
  end

  validates_each :content do |rec, attr, value|
    if rec.updates.for?(:content)
      rec.send :validate_content, value
    end
  end

  # private cards can't be connected to private cards with a different group
  validates_each :permissions do |rec, attr, value|
    if rec.updates.for?(:permissions)
      rec.errors.add :permissions, 'Insufficient permissions specifications' if value.length < 3
      reader,err = nil, nil
      value.each do |p|  #fixme-perm -- ugly - no alibi
        unless %w{ create read edit comment delete }.member?(p.task.to_s)
          rec.errors.add :permissions, "No such permission: #{p.task}"
        end
        if p.task == 'read' then reader = p.party end
        if p.party == nil and p.task!='comment'
          rec.errors.add :permission, "#{p.task} party can't be set to nil"
        end
      end


      if err
        rec.errors.add :permissions, "can't set read permissions on #{rec.name} to #{reader.cardname} because #{err}"
      end
    end
  end
  
  
  validates_each :typecode do |rec, attr, value|  
    # validate on update
    if rec.updates.for?(:typecode) and !rec.new_record?
      
      # invalid to change type when cards of this type exists
      if rec.typecode == 'Cardtype' and rec.extension and ::Card.find_by_typecode(rec.extension.codename)
        rec.errors.add :typecode, "can't be changed to #{value} for #{rec.name} because #{rec.name} is a Cardtype and cards of this type still exist"
      end
  
      rec.send :validate_typecode_change
=begin
      newcard = rec.send :clone_to_type, value
      newcard.valid?  # run all validations...
      rec.send :copy_errors_from, newcard
=end
    end

    # validate on update and create 
    if rec.updates.for?(:typecode) or rec.new_record?
      # invalid type recorded on create
      if rec.broken_cardtype
        rec.errors.add :typecode, "won't work.  There's no cardtype named '#{rec.broken_cardtype}'"
      end
      
      # invalid to change type when type is hard_templated
      if (rt = rec.right_template and rt.hard_template? and 
        value!=rt.typecode and !rec.allow_typecode_change)
        rec.errors.add :typecode, "can't be changed because #{rec.name} is hard tag templated to #{rec.right_template.typecode}"
      end        
      
      Rails.logger.debug "include for updates #{rec.name} #{value}"
#      include_type_module(value)
    end
  end  

  validates_each :key do |rec, attr, value|
    if value.empty?
      rec.errors.add :key, "key cannot be blank"
    elsif value != rec.name.to_key
      rec.errors.add :key, "wrong key '#{value}' for name #{rec.name}"
    end
  end
   
  def validate_destroy    
    if extension_type=='User' and extension and Revision.find_by_created_by( extension.id )
      errors.add :destroy, "Edits have been made with #{name}'s user account.<br>  Deleting this card would mess up our revision records."
      return false
    end           
    #should collect errors from dependent destroys here.  
    true
  end

  def validate_typecode_change  
  end
  
  def destroy_extension
    extension.destroy if extension
    extension = nil
    true
  end
  
  def validate_content( content )
  end
  
  class << self
=begin
    def class_for(name, field='codename')
      class_id = ( field.to_sym == :codename ? name :
          ( cardname = ::Cardtype.name_for_key(name.to_key) and
            ::Cardtype.classname_for(cardname) ) 
      )
      klass = Card.const_get(class_id)
      klass.allocate.is_a?(Card) ? klass : card_const_set(class_id)
    rescue Exception=>e
      nil
    end
=end

    def create_or_update args
      if c = Card[ args[:name] ]
        c.update_attributes args
        c
      else
        c= Card.new args
        c.save!
        #Card.create! args
        c
      end
    end

    def save_all_log_entry( name, content, prefix="\t" )
      "Card SaveAll: #{prefix}#{name}, " + (content||"").gsub("\n","")[0..50] + "\n"
    end
    
    def save_all data, opts = {}
      options = {
        :strategy => :create_or_update,  # :find_or_new, :create!, :update
        :plus_strategy => :create_or_update
      }.merge( opts )

      data.extend CardData
      plusses = data.extract_plus_data!

      log = ""
      time = Benchmark.measure do 
        Card.transaction do
          base_card = Card.send options[:strategy], data

          plusses.each do |plus_name, plus_data|
            plus_card_name = base_card.name + plus_name
            case plus_data
              when String;  
                Card.send options[:plus_strategy], :name=> plus_card_name, :content => plus_data
                log << save_all_log_entry( plus_card_name, plus_data)

              when Array;
                if block_given?
                  plus_data = plus_data..map{|x| yield(plus_name, x) }
                end
                card_args = {
                  :name => plus_card_name, 
                  :typecode => "Pointer",  
                  :content => plus_data.map{|x| "[[#{x}]]" }.join("\n")
                }
                Card.send options[:plus_strategy], card_args
                log << save_all_log_entry( card_args[:name], card_args[:content])
              when Hash;
                plus_data[:name] ||= plus_card_name
                Card.send options[:plus_strategy], plus_data
                log << save_all_log_entry( plus_data[:name], plus_data[:content])
            end
          end
        end
      end
      log = save_all_log_entry( data[:name], data[:content], prefix="(+#{plusses.size}, #{sprintf("%.3f",time.real)}s)  ") + log
      ActiveRecord::Base.logger.info log
    end
  end

end  

module CardData
  def extract_plus_data!
    keys.inject({}) {|h,k| h[k] = delete(k) if k =~ /^\+/; h }
  end
end

