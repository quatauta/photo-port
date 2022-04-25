require "dotenv/load"
require "flickr"

class Builders::FlickrPortfolio < SiteBuilder
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

  # use JSON file cache like bin/flickr
  def cache
    @@cache ||= Bridgetown::Cache.new(self.class.to_s)
  end

  def flickr_photosets(flickr, user_id)
    flickr.photosets.getList(user_id: user_id)["photoset"]
  end

  def flickr_photoset_photos(flickr, user_id, photoset)
    # use JSON file cache like bin/flickr
    cache_key = "flickr_photoset_#{photoset["id"]}_photos_#{photoset["date_update"]}"
    cache.getset(cache_key) do
      puts "fetching #{user_id} photoset #{photoset["id"]} photo list"
      flickr.photosets.getPhotos(user_id: user_id, photoset_id: photoset["id"], media: :photos, extras: "last_update")["photo"]
    end
  end

  def flickr_photo(flickr, photo)
    id = photo["id"]
    secret = photo["secret"]
    last_update = photo["last_update"]

    # use JSON file cache like bin/flickr
    cache_key = "flickr_photo_#{id}_#{last_update}"
    cache.getset(cache_key) do
      puts "fetching photo #{id} info"
      info = flickr.photos.getInfo(photo_id: id, secret: secret)

      info
    end
  end

  def flickr_photo_exif(flickr, photo)
    id = photo["id"]
    secret = photo["secret"]
    last_update = photo["last_update"]

    # use JSON file cache like bin/flickr
    cache_key = "flickr_photo_exif_#{id}_#{last_update}"
    cache.getset(cache_key) do
      exif = nil

      begin
        puts "fetching photo #{id} exif"
        exif = flickr.photos.getExif(photo_id: id, secret: secret)
      rescue
      end

      exif && exif["exif"].map { |value| value.respond_to?(:to_hash) ? value.to_hash : value }
    end
  end

  def flickr_photo_location(flickr, photo)
    id = photo["id"]
    secret = photo["secret"]
    last_update = photo["last_update"]

    # use JSON file cache like bin/flickr
    cache_key = "flickr_photo_location_#{id}_#{last_update}"
    cache.getset(cache_key) do
      location = nil

      begin
        puts "fetching photo #{id} location"
        location = flickr.photos.geo.getLocation(photo_id: id, secret: secret)
      rescue
      end

      location && location["location"].to_hash
    end
  end

  def flickr_photo_sizes(flickr, photo)
    id = photo["id"]
    last_update = photo["last_update"]

    # use JSON file cache like bin/flickr
    cache_key = "flickr_photo_sizes_#{id}_#{last_update}"
    cache.getset(cache_key) do
      sizes = nil

      begin
        puts "fetching photo #{id} sizes"
        sizes = flickr.photos.getSizes(photo_id: id)
      rescue
      end

      sizes && sizes["size"].map { |value| value.to_hash }
    end
  end

  def portfolio_slug(photoset)
    photoset["title"].sub(/\s*portfolio\s*/i, "").parameterize
  end

  def photo_slug(photo, index)
    photo["title"].parameterize
  end

  def portfolio_photo_resource(set, photo, index)
    "#{index + 1}-#{photo_slug(photo, index)}.md"
  end

  def portfolio_resource(set)
    "#{portfolio_slug(set)}.md"
  end

  def build
    builder_id = "builder://#{self.class.to_s.sub("::", ".")}"
    key = ENV["FLICKR_KEY"]
    secret = ENV["FLICKR_SECRET"]
    user = ENV["FLICKR_USER"]

    Flickr.cache = File.join(site.config["cache_dir"], "flickr-api.yml")
    flickr = ::Flickr.new(key, secret)
    photosets = flickr_photosets(flickr, user)

    photosets.select { |set| set["title"] =~ /portfolio/i }.each do |set|
      frontmatter = {
        layout: "default",
        pagination: {
          collection: portfolio_slug(set),
          per_page: 10,
          sort_field: "relative_url",
          sort_reverse: false
        },
      }
      add_resource :pages, portfolio_resource(set) do
        ___ frontmatter
        content PORTFOLIO_CONTENT
      end

      photoset_photos = flickr_photoset_photos(flickr, user, set)

      photoset_photos.each_with_index do |photo, index|
        info = flickr_photo(flickr, photo)
        exif = flickr_photo_exif(flickr, photo)

        prev_index = (index - 1) % photoset_photos.size
        next_index = (index + 1) % photoset_photos.size
        prev_photo = photoset_photos[prev_index]
        next_photo = photoset_photos[next_index]
        prev_id = "#{builder_id}/#{portfolio_photo_resource(set, prev_photo, prev_index)}"
        next_id = "#{builder_id}/#{portfolio_photo_resource(set, next_photo, next_index)}"

        frontmatter = {
          layout: "page",
          portfolio: portfolio_slug(set),
          title: info["title"],
          description: info["description"],
          flickr_id: info["id"],
          flickr_url: Flickr.url_photopage(info),
          source: Flickr.url_o(info),
          info: info.to_hash,
          exif: exif,
          prev: prev_id,
          next: next_id
        }

        add_resource portfolio_slug(set), portfolio_photo_resource(set, info, index) do
          ___ frontmatter
          content PHOTO_CONTENT
        end
      end
    end
  end
end
