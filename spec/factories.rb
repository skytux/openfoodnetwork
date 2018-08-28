require 'ffaker'
require 'spree/testing_support/factories'

# http://www.rubydoc.info/gems/factory_bot/file/GETTING_STARTED.md
#
# The spree_core gem defines factories in several files. For example:
#
# - lib/spree/core/testing_support/factories/calculator_factory.rb
#   * calculator
#   * no_amount_calculator
#
# - lib/spree/core/testing_support/factories/order_factory.rb
#   * order
#   * order_with_totals
#   * order_with_inventory_unit_shipped
#   * completed_order_with_totals
#
FactoryBot.define do
  factory :classification, class: Spree::Classification do
  end

  factory :order_cycle, :parent => :simple_order_cycle do
    coordinator_fees { [create(:enterprise_fee, enterprise: coordinator)] }

    after(:create) do |oc|
      # Suppliers
      supplier1 = create(:supplier_enterprise)
      supplier2 = create(:supplier_enterprise)

      # Incoming Exchanges
      ex1 = create(:exchange, :order_cycle => oc, :incoming => true,
                   :sender => supplier1, :receiver => oc.coordinator,
                   :receival_instructions => 'instructions 0')
      ex2 = create(:exchange, :order_cycle => oc, :incoming => true,
                   :sender => supplier2, :receiver => oc.coordinator,
                   :receival_instructions => 'instructions 1')
      ExchangeFee.create!(exchange: ex1,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex1.sender))
      ExchangeFee.create!(exchange: ex2,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex2.sender))

      # Distributors
      distributor1 = create(:distributor_enterprise)
      distributor2 = create(:distributor_enterprise)

      # Outgoing Exchanges
      ex3 = create(:exchange, :order_cycle => oc, :incoming => false,
                   :sender => oc.coordinator, :receiver => distributor1,
                   :pickup_time => 'time 0', :pickup_instructions => 'instructions 0')
      ex4 = create(:exchange, :order_cycle => oc, :incoming => false,
                   :sender => oc.coordinator, :receiver => distributor2,
                   :pickup_time => 'time 1', :pickup_instructions => 'instructions 1')
      ExchangeFee.create!(exchange: ex3,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex3.receiver))
      ExchangeFee.create!(exchange: ex4,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex4.receiver))

      # Products with images
      [ex1, ex2].each do |exchange|
        product = create(:product, supplier: exchange.sender)
        image = File.open(File.expand_path('../../app/assets/images/logo-white.png', __FILE__))
        Spree::Image.create({:viewable_id => product.master.id, :viewable_type => 'Spree::Variant', :alt => "position 1", :attachment => image, :position => 1})

        exchange.variants << product.variants.first
      end

      variants = [ex1, ex2].map(&:variants).flatten
      [ex3, ex4].each do |exchange|
        variants.each { |v| exchange.variants << v }
      end
    end
  end

  factory :order_cycle_with_overrides, parent: :order_cycle do
    after(:create) do |oc|
      oc.variants.each do |variant|
        create(:variant_override, variant: variant, hub: oc.distributors.first, price: variant.price + 100)
      end
    end
  end

  factory :simple_order_cycle, :class => OrderCycle do
    sequence(:name) { |n| "Order Cycle #{n}" }

    orders_open_at  { 1.day.ago }
    orders_close_at { 1.week.from_now }

    coordinator { Enterprise.is_distributor.first || FactoryBot.create(:distributor_enterprise) }

    transient do
      suppliers []
      distributors []
      variants []
    end

    after(:create) do |oc, proxy|
      proxy.suppliers.each do |supplier|
        ex = create(:exchange, :order_cycle => oc, :sender => supplier, :receiver => oc.coordinator, :incoming => true, :receival_instructions => 'instructions')
        proxy.variants.each { |v| ex.variants << v }
      end

      proxy.distributors.each do |distributor|
        ex = create(:exchange, :order_cycle => oc, :sender => oc.coordinator, :receiver => distributor, :incoming => false, :pickup_time => 'time', :pickup_instructions => 'instructions')
        proxy.variants.each { |v| ex.variants << v }
      end
    end
  end

  factory :undated_order_cycle, parent: :simple_order_cycle do
    orders_open_at  nil
    orders_close_at nil
  end

  factory :upcoming_order_cycle, parent: :simple_order_cycle do
    orders_open_at  { 1.week.from_now }
    orders_close_at { 2.weeks.from_now }
  end

  factory :open_order_cycle, parent: :simple_order_cycle do
    orders_open_at  { 1.week.ago }
    orders_close_at { 1.week.from_now }
  end

  factory :closed_order_cycle, parent: :simple_order_cycle do
    orders_open_at  { 2.weeks.ago }
    orders_close_at { 1.week.ago }
  end

  factory :exchange, :class => Exchange do
    incoming    false
    order_cycle { OrderCycle.first || FactoryBot.create(:simple_order_cycle) }
    sender      { incoming ? FactoryBot.create(:enterprise) : order_cycle.coordinator }
    receiver    { incoming ? order_cycle.coordinator : FactoryBot.create(:enterprise) }
  end

  factory :schedule, class: Schedule do
    sequence(:name) { |n| "Schedule #{n}" }
    order_cycles { [OrderCycle.first || FactoryBot.create(:simple_order_cycle)] }
  end

  factory :subscription, :class => Subscription do
    shop { create :enterprise }
    schedule { create(:schedule, order_cycles: [create(:simple_order_cycle, coordinator: shop)]) }
    customer { create(:customer, enterprise: shop) }
    bill_address { create(:address) }
    ship_address { create(:address) }
    payment_method { create(:payment_method, distributors: [shop]) }
    shipping_method { create(:shipping_method, distributors: [shop]) }
    begins_at { 1.month.ago }

    transient do
      with_items false
      with_proxy_orders false
    end

    after(:create) do |subscription, proxy|
      if proxy.with_items
        subscription.subscription_line_items = build_list(:subscription_line_item, 3, subscription: subscription)
        subscription.order_cycles.each do |oc|
          ex = oc.exchanges.outgoing.find_by_sender_id_and_receiver_id(subscription.shop_id, subscription.shop_id) ||
            create(:exchange, :order_cycle => oc, :sender => subscription.shop, :receiver => subscription.shop, :incoming => false, :pickup_time => 'time', :pickup_instructions => 'instructions')
          subscription.subscription_line_items.each { |sli| ex.variants << sli.variant }
        end
      end

      if proxy.with_proxy_orders
        subscription.order_cycles.each do |oc|
          subscription.proxy_orders << create(:proxy_order, subscription: subscription, order_cycle: oc)
        end
      end
    end
  end

  factory :subscription_line_item, :class => SubscriptionLineItem do
    subscription
    variant
    quantity 1
  end

  factory :proxy_order, :class => ProxyOrder do
    subscription
    order_cycle { subscription.order_cycles.first }
    before(:create) do |proxy_order, proxy|
      if proxy_order.order
        proxy_order.order.update_attribute(:order_cycle_id, proxy_order.order_cycle_id)
      end
    end
  end

  factory :variant_override, :class => VariantOverride do
    price         77.77
    count_on_hand 11111
    default_stock 2000
    resettable  false
  end

  factory :inventory_item, :class => InventoryItem do
    enterprise
    variant
    visible true
  end

  factory :enterprise, :class => Enterprise do
    owner { FactoryBot.create :user }
    sequence(:name) { |n| "Enterprise #{n}" }
    sells 'any'
    description 'enterprise'
    long_description '<p>Hello, world!</p><p>This is a paragraph.</p>'
    address { FactoryBot.create(:address) }
  end

  factory :supplier_enterprise, :parent => :enterprise do
    is_primary_producer true
    sells "none"
  end

  factory :distributor_enterprise, :parent => :enterprise do
    is_primary_producer false
    sells "any"

    transient do
      with_payment_and_shipping false
    end

    after(:create) do |enterprise, proxy|
      if proxy.with_payment_and_shipping
        create(:payment_method,  distributors: [enterprise])
        create(:shipping_method, distributors: [enterprise])
      end
    end
  end

  factory :enterprise_relationship do
  end

  factory :enterprise_role do
  end

  factory :enterprise_group, :class => EnterpriseGroup do
    name 'Enterprise group'
    sequence(:permalink) { |n| "group#{n}" }
    description 'this is a group'
    on_front_page false
    address { FactoryBot.build(:address) }
  end

  sequence(:calculator_amount)
  factory :calculator_per_item, class: Spree::Calculator::PerItem do
    preferred_amount { generate(:calculator_amount) }
  end

  factory :enterprise_fee, :class => EnterpriseFee do
    transient { amount nil }

    sequence(:name) { |n| "Enterprise fee #{n}" }
    sequence(:fee_type) { |n| EnterpriseFee::FEE_TYPES[n % EnterpriseFee::FEE_TYPES.count] }

    enterprise { Enterprise.first || FactoryBot.create(:supplier_enterprise) }
    calculator { build(:calculator_per_item, preferred_amount: amount) }

    after(:create) { |ef| ef.calculator.save! }
  end

  factory :product_distribution, :class => ProductDistribution do
    product         { |pd| Spree::Product.first || FactoryBot.create(:product) }
    distributor     { |pd| Enterprise.is_distributor.first || FactoryBot.create(:distributor_enterprise) }
    enterprise_fee  { |pd| FactoryBot.create(:enterprise_fee, enterprise: pd.distributor) }
  end

  factory :adjustment_metadata, :class => AdjustmentMetadata do
    adjustment { FactoryBot.create(:adjustment) }
    enterprise { FactoryBot.create(:distributor_enterprise) }
    fee_name 'fee'
    fee_type 'packing'
    enterprise_role 'distributor'
  end

  factory :weight_calculator, :class => OpenFoodNetwork::Calculator::Weight do
    after(:build)  { |c| c.set_preference(:per_kg, 0.5) }
    after(:create) { |c| c.set_preference(:per_kg, 0.5); c.save! }
  end

  factory :order_with_totals_and_distribution, :parent => :order do #possibly called :order_with_line_items in newer Spree
    distributor { create(:distributor_enterprise) }
    order_cycle { create(:simple_order_cycle) }

    after(:create) do |order|
      p = create(:simple_product, :distributors => [order.distributor])
      FactoryBot.create(:line_item, :order => order, :product => p)
      order.reload
    end
  end

  factory :order_with_distributor, :parent => :order do
    distributor { create(:distributor_enterprise) }
  end

  factory :order_with_taxes, parent: :completed_order_with_totals do
    ignore do
      product_price 0
      tax_rate_amount 0
      tax_rate_name ""
    end

    distributor { create(:distributor_enterprise) }
    order_cycle { create(:simple_order_cycle) }

    after(:create) do |order, proxy|
      order.distributor.update_attribute(:charges_sales_tax, true)
      Spree::Zone.global.update_attribute(:default_tax, true)

      p = FactoryBot.create(:taxed_product, zone: Spree::Zone.global, price: proxy.product_price, tax_rate_amount: proxy.tax_rate_amount, tax_rate_name: proxy.tax_rate_name, distributors: [order.distributor])
      FactoryBot.create(:line_item, order: order, product: p, price: p.price)
      order.reload
    end
  end

  factory :order_with_credit_payment, parent: :completed_order_with_totals do
    distributor { create(:distributor_enterprise)}
    order_cycle { create(:simple_order_cycle) }

    after(:create) do |order|
      create(:payment, amount: order.total + 10000, order: order, state: "completed")
      order.reload
    end
  end

  factory :order_without_full_payment, parent: :completed_order_with_totals do
    distributor { create(:distributor_enterprise)}
    order_cycle { create(:simple_order_cycle) }

    after(:create) do |order|
      create(:payment, amount: order.total - 1, order: order, state: "completed")
      order.reload
    end
  end

  factory :completed_order_with_fees, parent: :order_with_totals_and_distribution do
    transient do
      shipping_fee 3
      payment_fee 5
    end

    shipping_method do
      shipping_calculator = build(:calculator_per_item, preferred_amount: shipping_fee)
      create(:shipping_method, calculator: shipping_calculator, require_ship_address: false, distributors: [distributor])
    end

    after(:create) do |order, evaluator|
      create(:line_item, order: order)
      order.create_shipment!
      payment_calculator = build(:calculator_per_item, preferred_amount: evaluator.payment_fee)
      payment_method = create(:payment_method, calculator: payment_calculator)
      create(:payment, order: order, amount: order.total, payment_method: payment_method, state: 'checkout')
      while !order.completed? do break unless order.next! end
    end
  end

  factory :zone_with_member, :parent => :zone do
    default_tax true

    after(:create) do |zone|
      Spree::ZoneMember.create!(zone: zone, zoneable: Spree::Country.find_by_name('Australia'))
    end
  end

  factory :taxed_product, :parent => :product do
    transient do
      tax_rate_amount 0
      tax_rate_name ""
      zone nil
    end

    tax_category { create(:tax_category) }

    after(:create) do |product, proxy|
      raise "taxed_product factory requires a zone" unless proxy.zone
      create(:tax_rate, amount: proxy.tax_rate_amount, tax_category: product.tax_category, included_in_price: true, calculator: Spree::Calculator::DefaultTax.new, zone: proxy.zone, name: proxy.tax_rate_name)
    end
  end

  factory :producer_property, class: ProducerProperty do
    value 'abc123'
    producer { create(:supplier_enterprise) }
    property
  end

  factory :customer, :class => Customer do
    email { Faker::Internet.email }
    enterprise
    code { SecureRandom.base64(150) }
    user
    bill_address { create(:address) }
  end

  factory :billable_period do
    begins_at { Time.zone.now.beginning_of_month }
    ends_at { Time.zone.now.beginning_of_month + 1.month }
    sells { 'any' }
    trial { false }
    enterprise
    owner { enterprise.owner }
    turnover { rand(100000).to_f/100 }
    account_invoice do
      AccountInvoice.where(user_id: owner_id, year: begins_at.year, month: begins_at.month).first ||
      FactoryBot.create(:account_invoice, user: owner, year: begins_at.year, month: begins_at.month)
    end
  end

  factory :account_invoice do
    user { FactoryBot.create :user }
    year { 2000 + rand(100) }
    month { 1 + rand(12) }
  end

  factory :filter_order_cycles_tag_rule, class: TagRule::FilterOrderCycles do
    enterprise { FactoryBot.create :distributor_enterprise }
  end

  factory :filter_shipping_methods_tag_rule, class: TagRule::FilterShippingMethods do
    enterprise { FactoryBot.create :distributor_enterprise }
  end

  factory :filter_products_tag_rule, class: TagRule::FilterProducts do
    enterprise { FactoryBot.create :distributor_enterprise }
  end

  factory :filter_payment_methods_tag_rule, class: TagRule::FilterPaymentMethods do
    enterprise { FactoryBot.create :distributor_enterprise }
  end

  factory :tag_rule, class: TagRule::DiscountOrder do
    enterprise { FactoryBot.create :distributor_enterprise }
    before(:create) do |tr|
      tr.calculator = Spree::Calculator::FlatPercentItemTotal.new(calculable: tr)
    end
  end

  factory :stripe_payment_method, :class => Spree::Gateway::StripeConnect do
    name 'Stripe'
    environment 'test'
  end

  factory :stripe_account do
    enterprise { FactoryBot.create :distributor_enterprise }
    stripe_user_id "abc123"
    stripe_publishable_key "xyz456"
  end

  factory :product_with_image, parent: :product do
    after(:create) do |product|
      image = File.open(Rails.root.join('app', 'assets', 'images', 'logo-white.png'))
      Spree::Image.create(attachment: image, viewable_id: product.master.id, viewable_type: 'Spree::Variant')
    end
  end

  factory :simple_product, parent: :base_product do
    transient do
      on_demand { false }
      on_hand { 5 }
    end
    after(:create) do |product, evaluator|
      product.variants.first.tap do |variant|
        variant.on_demand = evaluator.on_demand
        variant.count_on_hand = evaluator.on_hand
        variant.save
      end
    end
  end
end


FactoryBot.modify do
  factory :product do
    primary_taxon { Spree::Taxon.first || FactoryBot.create(:taxon) }
  end

  factory :base_product do
    # Fix product factory name sequence with Kernel.rand so it is not interpreted as a Spree::Product method
    # Pull request: https://github.com/spree/spree/pull/1964
    # When this fix has been merged into a version of Spree that we're using, this line can be removed.
    sequence(:name) { |n| "Product ##{n} - #{Kernel.rand(9999)}" }

    supplier { Enterprise.is_primary_producer.first || FactoryBot.create(:supplier_enterprise) }
    primary_taxon { Spree::Taxon.first || FactoryBot.create(:taxon) }

    unit_value 1
    unit_description ''

    variant_unit 'weight'
    variant_unit_scale 1
    variant_unit_name ''
  end

  factory :variant do
    transient do
      on_demand { false }
      on_hand { 5 }
    end

    unit_value 1
    unit_description ''

    after(:create) do |variant, evaluator|
      variant.on_demand = evaluator.on_demand
      variant.count_on_hand = evaluator.on_hand
      variant.save
    end
  end

  factory :shipping_method do
    distributors { [Enterprise.is_distributor.first || FactoryBot.create(:distributor_enterprise)] }
    display_on ''
  end

  factory :address do
    state { Spree::State.find_by_name 'Victoria' }
    country { Spree::Country.find_by_name 'Australia' || Spree::Country.first }
  end

  factory :payment do
    transient do
      distributor { order.distributor || Enterprise.is_distributor.first || FactoryBot.create(:distributor_enterprise) }
    end
    payment_method { FactoryBot.create(:payment_method, distributors: [distributor]) }
  end

  factory :payment_method do
    distributors { [Enterprise.is_distributor.first || FactoryBot.create(:distributor_enterprise)] }
  end

  factory :option_type do
    # Prevent inconsistent ordering in specs when all option types have the same (0) position
    sequence(:position)
  end

  factory :user do
    confirmation_sent_at '1970-01-01 00:00:00'
    confirmed_at '1970-01-01 00:00:01'

    after(:create) do |user|
      user.spree_roles.clear # Remove admin role
    end
  end

  factory :admin_user do
    confirmation_sent_at '1970-01-01 00:00:00'
    confirmed_at '1970-01-01 00:00:01'

    after(:create) do |user|
      user.spree_roles << Spree::Role.find_or_create_by_name!('admin')
    end
  end
end
