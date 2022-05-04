---
layout: default
---

<div class="mx-auto">
  <div class="grid grid-cols-1 gap-1 lg:grid-cols-2 2xl:grid-cols-3">
{% assign portfolios = site.resources | map: "portfolio" | compact | sort | uniq -%}
{% for portfolio in portfolios -%}
{%   assign photos = site.resources | where: "portfolio", portfolio | reverse -%}
{%   for photo in photos limit:2 -%}
{%     if photo.data.info.rotation == 90 or photo.data.info.rotation == 270 -%}
{%       assign class = "row-span-2" -%}
{%     endif -%}
{%     assign portfolio_url = portfolio | relative_url | append: "/" -%}
{%     render "flickr_portfolio_thumbnail",
              source:        photo.data.source,
              portfolio_url: portfolio_url,
              id:            photo.data.slug,
              title:         photo.data.title,
              class:         class -%}
{%   endfor -%}
{% endfor -%}
  </div>
</div>
