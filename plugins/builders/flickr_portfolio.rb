require "date"
require "dotenv/load"
require "flickr"

class Builders::FlickrPortfolio < SiteBuilder
  CONFIG_DEFAULTS = {
    flickr_portfolio: {
      api_key: nil,
      api_secret: nil,
      user: nil,
      api_cache: File.join(".bridgetown-cache", "flickr-api.yml")
    }
  }

  PHOTO_CONTENT = <<~EOS
    {% assign make          = resource.data.exif | where: "tag", "Make"                    | map: "raw"   | first | capitalize -%}
    {% assign model         = resource.data.exif | where: "tag", "Model"                   | map: "raw"   | first -%}
    {% assign aperture      = resource.data.exif | where: "tag", "FNumber"                 | map: "clean" | first -%}
    {% assign focal_length  = resource.data.exif | where: "tag", "FocalLengthIn35mmFormat" | map: "raw"   | first -%}
    {% assign shutter_speed = resource.data.exif | where: "tag", "ExposureTime"            | map: "raw"   | first -%}
    {% assign iso           = resource.data.exif | where: "tag", "ISO"                     | map: "raw"   | first -%}
    {% render "flickr_photo", id:            resource.data.slug,
                              flickr_url:    resource.data.flickr_url,
                              source:        resource.data.source,
                              title:         resource.data.title,
                              description:   resource.data.description,
                              portfolio:     resource.data.portfolio,
                              make:          make,
                              model:         model,
                              aperture:      aperture,
                              focal_length:  focal_length,
                              shutter_speed: shutter_speed,
                              iso:           iso,
                              prev_url:      resource.previous.relative_url,
                              next_url:      resource.next.relative_url -%}
  EOS

  PORTFOLIO_CONTENT = <<~EOS
    <div class="mx-auto">
    <div class="grid grid-cols-1 gap-1 lg:grid-cols-2 2xl:grid-cols-3">
    {% for photo in paginator.resources -%}
    {%   if photo.data.info.rotation == 90 or photo.data.info.rotation == 270 -%}
    {%     assign class = "row-span-2" -%}
    {%   endif -%}
    {%   render "flickr_portfolio_thumbnail",
                 source:    photo.data.source,
                 portfolio_url: resource.relative_url,
                 id:        photo.data.slug,
                 title:     photo.data.title,
                 class:     class -%}
    {% endfor -%}
    </div>
    </div>
  EOS

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

  def build
    key = config["flickr_portfolio"]["api_key"]&.gsub("ENV.FLICKR_API_KEY", ENV["FLICKR_API_KEY"])
    secret = config["flickr_portfolio"]["api_secret"]&.gsub("ENV.FLICKR_API_SECRET", ENV["FLICKR_API_SECRET"])
    user = config["flickr_portfolio"]["user_id"]&.gsub("ENV.FLICKR_USER_ID", ENV["FLICKR_USER_ID"])

    Flickr.cache = config["flickr_portfolio"]["api_cache"]
    flickr = ::Flickr.new(key, secret)
    photosets = flickr_photosets(flickr, user)

    photosets.select { |set| set["title"] =~ /portfolio/i }.each do |set|
      add_resource :pages, "#{portfolio_slug(set)}.md" do
        layout "default"
        pagination from: -> { {collection: portfolio_slug(set), per_page: 10, sort_field: "relative_url", sort_reverse: false} }
        content PORTFOLIO_CONTENT
      end

      photoset_photos = flickr_photoset_photos(flickr, user, set)

      photoset_photos.each_with_index do |photo, index|
        info = flickr_photo(flickr, photo)
        exif = flickr_photo_exif(flickr, photo)&.to_hash&.fetch("exif", nil)
        location = flickr_photo_location(flickr, photo)&.to_hash&.fetch("location", nil)

        frontmatter = {
          layout: "page",
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
          content PHOTO_CONTENT
        end
      end
    end
  end
end
