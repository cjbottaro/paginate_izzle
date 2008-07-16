require 'paginate_izzle'

ActiveRecord::Base.extend PaginateIzzle::ActiveRecordMethods
ActionView::Base.send :include, PaginateIzzle::ViewHelperMethods