require "date"
require "dotenv/load"
require "flickr"

class Builders::FlickrPortfolio < SiteBuilder
  CONFIG_DEFAULTS = {
    flickr_portfolio: {
      api_cache_file: File.join(".bridgetown-cache", "flickr-api.yml"),
      layout: {
        photo: "flickr_photo",
        portfolio: "flickr_portfolio"
      }
    }
  }

  def build
    hook :site, :post_read do
      flickr_api_key = ENV.fetch("FLICKR_API_KEY")
      flickr_api_secret = ENV.fetch("FLICKR_API_SECRET")
      flickr_user_id = site.metadata.flickr_user_id
      layout_flickr_photo = config["flickr_portfolio"]["layout"]["photo"]
      layout_flickr_portfolio = config["flickr_portfolio"]["layout"]["portfolio"]
      Flickr.cache = config["flickr_portfolio"]["api_cache_file"]

      flickr = ::Flickr.new(flickr_api_key, flickr_api_secret)

      flickr_photosets(flickr, flickr_user_id).select { |set| set["title"] =~ /portfolio/i }.each do |set|
        add_portfolio_resource(set, layout_flickr_portfolio)

        flickr_photoset_photos(flickr, flickr_user_id, set).each_with_index do |photo, index|
          info = flickr_photo_info(flickr, photo)
          exif = flickr_photo_exif(flickr, photo)&.to_hash&.fetch("exif", nil)
          location = flickr_photo_location(flickr, photo)&.to_hash&.fetch("location", nil)
          sizes = flickr_photo_sizes(flickr, photo)&.to_hash&.fetch("size", nil)&.map { |s| s&.to_hash }

          add_photo_resource(set: set, photo: photo, index: index, info: info, exif: exif, location: location, sizes: sizes, layout: layout_flickr_photo)
        end
      end
    end
  end

  def add_photo_resource(set:, photo:, index:, info:, exif:, location:, sizes:, layout:)
    frontmatter = {
      layout: layout,
      portfolio: portfolio_slug(set),
      title: info["title"],
      description: info["description"],
      flickr_id: info["id"],
      flickr_url: Flickr.url_photopage(info),
      source: Flickr.url_o(info),
      info: info&.to_hash,
      exif: exif,
      location: location&.to_hash,
      sizes: sizes
    }

    add_resource portfolio_slug(set), "#{index + 1}-#{info["title"].parameterize}.md" do
      ___ frontmatter
    end
  end

  def add_portfolio_resource(set, layout)
    frontmatter = {
      layout: layout,
      portfolio: portfolio_slug(set),
      pagination: {collection: portfolio_slug(set), per_page: 10, sort_field: "relative_url", sort_reverse: false}
    }

    add_resource "pages", "#{portfolio_slug(set)}.md" do
      ___ frontmatter
    end
  end

  def flickr_photosets(flickr, user_id)
    cache.getset("user_#{user_id}_photosets_#{Date.today}") do
      log("fetching #{user_id} photoset list")
      flickr.photosets.getList(user_id: user_id)["photoset"]
    end
  end

  def flickr_photoset_photos(flickr, user_id, photoset)
    cache.getset("photoset_#{photoset["id"]}_photos_#{photoset["date_update"]}") do
      log("fetching #{user_id} photoset #{photoset["id"]} photo list")
      flickr.photosets.getPhotos(user_id: user_id, photoset_id: photoset["id"], media: :photos, extras: "last_update")["photo"]
    end
  end

  def flickr_photo_info(flickr, photo)
    cache.getset("photo_#{photo["id"]}_info_#{photo["last_update"]}") do
      log("fetching photo #{photo["id"]} info")
      flickr.photos.getInfo(photo_id: photo["id"], secret: photo["secret"])
    end
  end

  def flickr_photo_exif(flickr, photo)
    cache.getset("photo_#{photo["id"]}_exif_#{photo["last_update"]}") do
      log("fetching photo #{photo["id"]} exif")
      flickr.photos.getExif(photo_id: photo["id"], secret: photo["secret"])
    rescue Flickr::FailedResponse => error
      raise unless /getExif.*Photo has no exif information/i.match?(error.message)
    end
  end

  def flickr_photo_location(flickr, photo)
    cache.getset("photo_#{photo["id"]}_location_#{photo["last_update"]}") do
      log("fetching photo #{photo["id"]} location")
      flickr.photos.geo.getLocation(photo_id: photo["id"], secret: photo["secret"])
    rescue Flickr::FailedResponse => error
      raise unless /getLocation.*Photo has no location information/i.match?(error.message)
    end
  end

  def flickr_photo_sizes(flickr, photo)
    cache.getset("photo_#{photo["id"]}_sizes_#{photo["last_update"]}") do
      log("fetching photo #{photo["id"]} sizes")
      flickr.photos.getSizes(photo_id: photo["id"])
    rescue Flickr::FailedResponse => error
      raise unless /getLocation.*Photo has no size information/i.match?(error.message)
    end
  end

  def portfolio_slug(photoset)
    photoset["title"].sub(/\s*portfolio\s*/i, "").parameterize
  end

  private

  def log(message)
    Bridgetown.logger.info("#{self.class}:", message)
  end

  def cache
    @@cache ||= Bridgetown::Cache.new(self.class.to_s)
  end
end
