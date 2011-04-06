class Promotion < Activator
  has_many  :promotion_credits, :as => :source
  calculated_adjustments
  alias credits promotion_credits


  MATCH_POLICIES = %w(all any)

  preference :combine, :boolean, :default => false
  preference :usage_limit, :integer
  preference :match_policy, :string, :default => MATCH_POLICIES.first
  preference :code, :string

  [:combine, :usage_limit, :match_policy, :code].each do |field|
    alias_method field, "preferred_#{field}"
    alias_method "#{field}=", "preferred_#{field}="
  end


  has_many :promotion_rules, :foreign_key => 'activator_id', :autosave => true
  alias_method :rules, :promotion_rules
  accepts_nested_attributes_for :promotion_rules

  has_many :promotion_actions, :foreign_key => 'activator_id', :autosave => true
  alias_method :actions, :promotion_actions
  accepts_nested_attributes_for :promotion_actions

  # TODO: This shouldn't be necessary with :autosave option but nested attribute updating of actions is broken without it
  after_save :save_rules_and_actions
  def save_rules_and_actions
    (rules + actions).each &:save
  end


  validates :name, :presence => true

  # TODO: Remove that after fix for https://rails.lighthouseapp.com/projects/8994/tickets/4329-has_many-through-association-does-not-link-models-on-association-save
  # is provided
  def save(*)
    if super
      promotion_rules.each { |p| p.save }
    end
  end


  def activate(payload)
    order = payload.delete(:order)
    if eligible?(order, payload)
      # TODO: perform promotion actions here
    end
  end

  def eligible?(order, options = {})
    !expired? && rules_are_eligible?(order, options = {})
  end

  def credits_count
    credits.with_order.count
  end

  def rules_are_eligible?(order, options = {})
    return true if rules.none?
    if match_policy == 'all'
      rules.all?{|r| r.eligible?(order, options)}
    else
      rules.any?{|r| r.eligible?(order, options)}
    end
  end

  def create_discount(order)
    return if order.promotion_credit_exists?(self)
    if eligible?(order) and amount = calculator.compute(order)
      amount = order.item_total if amount > order.item_total
      order.promotion_credits.reload.clear unless combine? and order.promotion_credits.all? { |credit| credit.source.combine? }
      order.update!
      PromotionCredit.create!({
          :label => "#{I18n.t(:coupon)} (#{code})",
          :source => self,
          :amount => -amount.abs,
          :order => order
        })
    end
  end



  # Products assigned to all product rules
  def products
    @products ||= rules.of_type("Promotion::Rules::Product").map(&:products).flatten.uniq
  end

end
