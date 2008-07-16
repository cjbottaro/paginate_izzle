module PaginateIzzle
  
  def self.named_scope_paginate_hash(page_no, per_page)
    offset = (page_no.to_i - 1) * per_page.to_i
    { :offset => offset,
      :limit  => per_page }
  end
  
  # This class is used by the pagination partial to render the widget.  The widget being the html for << Previous 1 2 ... 10 11 12 Next >>
  class Paginator
    attr_accessor :options
    
    DEFAULT_OPTIONS = {
      :prev_label => "<< Previous",
      :next_label => "Next >>",
      :inner_window => 3,
      :outer_window => 1,
      :param_name => "page",
      :html_class => "paginator",
      :html_id => "paginator",
      :partial => 'shared/default_paginator'
    }
    
    # <tt>page</tt> is the current page you're on.
    # <tt>per_page</tt> is how many records you want per page.
    # <tt>count</tt> is how many records there are total across all pages.
    # <tt>options</tt> rendering options (see <tt>DEFAULT_OPTIONS</tt> and <tt>Paginator#page</tt>).
    def initialize(page, per_page, count, options = {})
      @page, @per_page, @count, @options = page, per_page, count, options.reverse_merge(DEFAULT_OPTIONS)
    end
    
    # Returns an array that pagination widget partial will use to render.
    #  pages(1, 100, 50, 1, 3)
    #  >> [1, 2, '...', 47, 48, 49, 50, 51, 52, 53, '...', 99, 100]
    # Where...
    #  first_page, last_page  [1, 2, '...', 47, 48, 49, 50, 51, 52, 53, '...', 99, 100]
    #                          ^                                                   ^^^
    #  page                   [1, 2, '...', 47, 48, 49, 50, 51, 52, 53, '...', 99, 100]
    #                                                   ^^
    #  outer_window           [1, 2, '...', 47, 48, 49, 50, 51, 52, 53, '...', 99, 100]
    #                             ^                                            ^^
    #  inner_window           [1, 2, '...', 47, 48, 49, 50, 51, 52, 53, '...', 99, 100]
    #                                       ^^  ^^  ^^      ^^  ^^  ^^
    def pages(first_page, last_page, page, outer_window, inner_window)
      pages       = []

      pages << first_page
      pages += Array.new(outer_window) { |i| i + 1 }.collect{ |i| first_page + 1 }
      pages += Array.new(inner_window) { |i| i + 1 }.reverse.collect{ |i| page - i }
      pages << page
      pages += Array.new(inner_window) { |i| i + 1 }.collect{ |i| page + i }
      pages += Array.new(outer_window) { |i| i + 1 }.reverse.collect{ |i| last_page - i }
      pages << last_page

      pages = pages.reject { |page| page < first_page or page > last_page  }.uniq

      last = first_page - 1
      pages.inject([]) do |memo, page|
        memo << '...' if last != page - 1
        memo << page
        last = page
        memo
      end
      
    end
    
    # Calculates the last page based on the count and per_page values.
    def last_page
      (@count / @per_page.to_f).ceil
    end
    
    # Returns what partial to use to render the pagination widget.
    def partial
      @options[:partial]
    end
    
    # Returns the hash passed as locals to the pagination widget partial.
    def locals_hash
      { :page => @page,
        :pages => pages(1, last_page, @page, @options[:outer_window], @options[:inner_window]),
        :prev_label => @options[:prev_label],
        :next_label => @options[:next_label],
        :param_name => @options[:param_name],
        :html_id => @options[:html_id],
        :html_class => @options[:html_class] }
    end
  end
  
  module ActiveRecordMethods
    
    # Addes the named scope <tt>paginate</tt> and class inheritable attribute <tt>pagination_options</tt> to ActiveRecord::Base.
    def self.extended(mod)
      mod.class_eval do
        class_inheritable_hash :pagination_options
        named_scope :paginate, lambda { |page_no, per_page|
          PaginateIzzle::named_scope_paginate_hash(page_no, per_page)
        }
      end
    end
    
    # Set pagination options to a specific model.  This will create a named scope <tt>paginate</tt> that overrides the
    # one created on ActiveRecord::Base.  See Paginator::DEFAULT_OPTIONS for valid options, but <tt>:per_page</tt> is
    # probably the main one you want.
    def pagination(options = {})
      self.pagination_options = options.reverse_merge :per_page => nil
      class_eval do
        named_scope :paginate, lambda { |*args|
          page_no, per_page = args
          per_page = self.pagination_options[:per_page] if per_page.blank?
          raise ArgumentError, "per_page not set. Hint: set it in the call to pagination or as the second argument to paginate." if per_page.blank?
          PaginateIzzle::named_scope_paginate_hash(page_no, per_page)
        }
      end
    end
    
    # Returns a Paginator object that the pagination partial uses to render the widget.  Options passed here override
    # options passed into ActiveRecordMethods#pagination.
    # <tt>page_no</tt> is the page you are currently on.
    # <tt>count</tt> is the total number of records across all pages.
    # <tt>options</tt> are the rendering options, see Paginator::DEFAULT_OPTIONS.
    def paginator(page_no, count, options = {})
      options = options.reverse_merge :per_page => self.pagination_options[:per_page]
      Paginator.new(page_no, options[:per_page], count, options)
    end
    
  end
    
  module ViewHelperMethods
    
    # This view helper will render the pagination widget.  The options passed here will override the options passed in
    # ActiveRecordMethods#pagination or ActiveRecordMethods#paginator.
    # <tt>renderer</tt> is the Paginator object.
    # <tt>options</tt> are the rendering options, see Paginator::DEFAULT_OPTIONS.
    def render_paginator(renderer, options = {})
      renderer.options.merge!(options)
      render :partial => renderer.partial, :locals => renderer.locals_hash
    end
    
    # This is a helper that is meant to be called from the pagination widget partial.  It creates a link to a page
    # based on the current url.  If your current url is...
    #  /some/action?arg1=blah&arg2=bleh
    # Then...
    #  pagination_link_to('page five', 5, 'da_page')
    #  >> <a href="/some/action?arg1=blah&arg2=bleh&da_page=5">page five</a>
    def pagination_link_to(text, page, param_name = 'page')
      params = controller.request.parameters.reject{ |k, v| controller.request.path_parameters.keys.include?(k) }
      params[param_name] = page
      param_array = []
      params.each{ |k, v| param_array << "#{k}=#{v}" }
      link_to text, controller.request.path + '?' + param_array.join('&')
    end
    
  end
    
end