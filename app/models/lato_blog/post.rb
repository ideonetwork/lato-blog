module LatoBlog
  class Post < ApplicationRecord

    include Post::EntityHelpers
    include Post::SerializerHelpers

    # Validations:

    validates :title, presence: true, length: { maximum: 250 }

    validates :meta_permalink, presence: true, uniqueness: true, length: { maximum: 250 }
    validates :meta_status, presence: true, length: { maximum: 250 }, inclusion: { in: BLOG_POSTS_STATUS.values }
    validates :meta_language, presence: true, length: { maximum: 250 }, inclusion: { in: ([nil] + BLOG_LANGUAGES_IDENTIFIER) }

    # Relations:

    belongs_to :post_parent, foreign_key: :lato_blog_post_parent_id,
                             class_name: 'LatoBlog::PostParent'

    belongs_to :superuser_creator, foreign_key: :lato_core_superuser_creator_id,
                                   class_name: 'LatoCore::Superuser'

    has_many :post_fields, foreign_key: :lato_blog_post_id,
                           class_name: 'LatoBlog::PostField',
                           dependent: :destroy

    has_many :category_relations, foreign_key: :lato_blog_post_id,
                                  class_name: 'LatoBlog::CategoryPost',
                                  dependent: :destroy
    has_many :categories, through: :category_relations

    has_many :tag_relations, foreign_key: :lato_blog_post_id,
                             class_name: 'LatoBlog::TagPost',
                             dependent: :destroy
    has_many :tags, through: :tag_relations

    # Scopes:

    scope :published, -> { where(meta_status: BLOG_POSTS_STATUS[:published]) }
    scope :drafted, -> { where(meta_status: BLOG_POSTS_STATUS[:drafted]) }
    scope :deleted, -> { where(meta_status: BLOG_POSTS_STATUS[:deleted]) }

    # Callbacks:

    before_validation :check_meta_permalink, on: :create

    before_save do
      self.meta_permalink = meta_permalink.parameterize
      meta_status.downcase!
      meta_language.downcase!

      check_lato_blog_post_parent
    end

    after_save do
      blog__sync_config_post_fields_with_db_post_fields_for_post(self)
    end

    after_create do
      add_to_default_category
    end

    after_destroy do
      blog__clean_post_parents
    end

    private

    # This function check if current permalink is valid. If it is not valid it
    # generate a new from the post title.
    def check_meta_permalink
      candidate = (meta_permalink ? meta_permalink : title.parameterize)
      accepted = nil
      counter = 0

      while accepted.nil?
        if LatoBlog::Post.find_by(meta_permalink: candidate)
          counter = counter + 1
          candidate = "#{candidate}-#{counter}"
        else
          accepted = candidate
        end
      end

      self.meta_permalink = accepted
    end

    # This function check that the post parent exist and has not others post for the same language.
    def check_lato_blog_post_parent
      post_parent = LatoBlog::PostParent.find_by(id: lato_blog_post_parent_id)
      if !post_parent
        errors.add('Post parent', 'not exist for the post')
        throw :abort
        return
      end

      same_language_post = post_parent.posts.find_by(meta_language: meta_language)
      if same_language_post && same_language_post.id != id
        errors.add('Post parent', 'has another post for the same language')
        throw :abort
        return
      end
    end

    # This function add the post to the default category.
    def add_to_default_category
      default_category_parent = LatoBlog::CategoryParent.find_by(meta_default: true)
      return unless default_category_parent

      category = default_category_parent.categories.find_by(meta_language: meta_language)
      return unless category

      LatoBlog::CategoryPost.create(lato_blog_post_id: id, lato_blog_category_id: category.id)
    end

  end
end
