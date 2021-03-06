module Spree
  ProductsHelper.class_eval do
    # Return the price of the variant, overriding sprees price diff capability.
    # This will allways return the variant price as if the show_variant_full_price is set.
    def variant_price_diff(variant)
      "(#{Spree::Money.new(variant.price)})"
    end

    def product_has_variant_unit_option_type?(product)
      product.option_types.any? { |option_type| variant_unit_option_type? option_type }
    end

    def variant_unit_option_type?(option_type)
      Spree::Product.all_variant_unit_option_types.include? option_type
    end

    def product_variant_unit_options
      [[I18n.t(:weight), 'weight'],
       [I18n.t(:volume), 'volume'],
       [I18n.t(:items), 'items']]
    end
  end
end
