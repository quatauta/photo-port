require "date"
require "dotenv/load"
require "flickr"

class Builders::FlickrPortfolio < SiteBuilder
  CONFIG_DEFAULTS = {
    flickr_portfolio: {
      api_key: nil,
      api_secret: nil,
      user_id: nil,
      api_cache_file: File.join(".bridgetown-cache", "flickr-api.yml")
    }
  }

  def cache
    @@cache ||= Bridgetown::Cache.new(self.class.to_s)
  end

  def flickr_photosets(flickr, user_id)
    cache.getset("user_#{user_id}_photosets_#{Date.today}") do
      puts "fetching #{user_id} photoset list"
      flickr.photosets.getList(user_id: user_id)["photoset"]
    end
  end

  def flickr_photoset_photos(flickr, user_id, photoset)
    cache.getset("photoset_#{photoset["id"]}_photos_#{photoset["date_update"]}") do
      puts "fetching #{user_id} photoset #{photoset["id"]} photo list"
      flickr.photosets.getPhotos(user_id: user_id, photoset_id: photoset["id"], media: :photos, extras: "last_update")["photo"]
    end
  end

  def flickr_photo(flickr, photo)
    cache.getset("photo_#{photo["id"]}_info_#{photo["last_update"]}") do
      puts "fetching photo #{photo["id"]} info"
      flickr.photos.getInfo(photo_id: photo["id"], secret: photo["secret"])
    end
  end

  def flickr_photo_exif(flickr, photo)
    cache.getset("photo_#{photo["id"]}_exif_#{photo["last_update"]}") do
      puts "fetching photo #{photo["id"]} exif"
      flickr.photos.getExif(photo_id: photo["id"], secret: photo["secret"])
    rescue
      # getExif API call with fail with error if exif information is not available
    end
  end

  def flickr_photo_location(flickr, photo)
    cache.getset("photo_#{photo["id"]}_location_#{photo["last_update"]}") do
      puts "fetching photo #{photo["id"]} location"
      flickr.photos.geo.getLocation(photo_id: photo["id"], secret: photo["secret"])
    rescue
      # getLocation API call with fail with error if location information is not available
    end
  end

  def portfolio_slug(photoset)
    photoset["title"].sub(/\s*portfolio\s*/i, "").parameterize
  end

  def substitute_environment_variable(text, variable_name)
    pattern_prefix = '(\A|\W)ENV.'
    pattern_variable_name = Regexp.quote(variable_name.to_s)
    pattern_suffix = '(\W|\z)'
    regex = Regexp.new(pattern_prefix + pattern_variable_name + pattern_suffix)

    text&.gsub(regex, ENV.fetch(variable_name))
  end

  def build
    flickr_api_key = substitute_environment_variable(config["flickr_portfolio"]["api_key"], "FLICKR_API_KEY")
    flickr_api_secret = substitute_environment_variable(config["flickr_portfolio"]["api_secret"], "FLICKR_API_SECRET")
    flickr_user_id = substitute_environment_variable(config["flickr_portfolio"]["user_id"], "FLICKR_USER_ID")
    Flickr.cache = config["flickr_portfolio"]["api_cache_file"]

    flickr = ::Flickr.new(flickr_api_key, flickr_api_secret)
    photosets = flickr_photosets(flickr, flickr_user_id)

    photosets.select { |set| set["title"] =~ /portfolio/i }.each do |set|
      add_resource :pages, "#{portfolio_slug(set)}.md" do
        layout "flickr_portfolio"
        pagination from: -> { {collection: portfolio_slug(set), per_page: 10, sort_field: "relative_url", sort_reverse: false} }
      end

      photoset_photos = flickr_photoset_photos(flickr, flickr_user_id, set)

      photoset_photos.each_with_index do |photo, index|
        info = flickr_photo(flickr, photo)
        exif = flickr_photo_exif(flickr, photo)&.to_hash&.fetch("exif", nil)
        location = flickr_photo_location(flickr, photo)&.to_hash&.fetch("location", nil)

        frontmatter = {
          layout: "flickr_photo",
          portfolio: portfolio_slug(set),
          title: info["title"],
          description: info["description"],
          flickr_id: info["id"],
          flickr_url: Flickr.url_photopage(info),
          source: Flickr.url_o(info),
          info: info&.to_hash,
          exif: exif,
          location: location&.to_hash
        }

        add_resource portfolio_slug(set), "#{index + 1}-#{info["title"].parameterize}.md" do
          ___ frontmatter
        end
      end
    end
  end
end
