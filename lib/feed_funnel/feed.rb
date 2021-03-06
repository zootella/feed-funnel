require 'hpricot'

class FeedFunnel::Feed
  attr_reader :h, :items

  def initialize(rss)
    self.parse(rss)
  end

  def parse(rss)
    @h = Hpricot::XML(rss)
    @items = (h / :item).map {|i| Item.new(i) }
  end
  
  def add_title(new_title)
    self.h.search("channel/title").remove
    self.h.at('channel').children.unshift Hpricot.build { tag!("title", new_title) }
  end

  def add_funnel_namespace
    self.h.at('rss').set_attribute 'xmlns:combinificator', "http://combinificator.com/rss"
  end

  def add_funnel_origlinks(feeds)
    self.h.at('channel').children.unshift(Hpricot.build { tag!("combinificator:group") })
    
    sources = []
    (feeds << self).each do |feed|
      if link = feed.h.at('atom:link[@rel=self]') || feed.h.at('atom10:link[@rel=self]')
        item = feed.h.at('item')

        source_attrs                = {}
        source_attrs['url']         = link['href']
        source_attrs['isPrimary']   = (feed == self ? 'true' : 'false')

        enclosure_attrs             = {}
        enclosure_attrs['size']     = (item.at('enclosure')['length'] rescue nil) || (item.at('media:content')['fileSize'] rescue nil)
        enclosure_attrs['type']     = (item.at('enclosure')['type'] rescue nil) || (item.at('media:content')['type'] rescue nil)
        enclosure_attrs['url']      = (item.at('enclosure')['url'] rescue nil) || (item.at('media:content')['url'] rescue nil)
        enclosure_attrs['duration'] = (item.at('enclosure')['duration'] rescue nil) || (item.at('media:content')['duration'] rescue nil) # NOTE: we could scrap for <itunes:duration> too, if you want

        source = Hpricot.build { 
          tag!("combinificator:source", source_attrs) {
            tag!("combinificator:enclosure", enclosure_attrs)
          }
        }

        self.h.at('combinificator:group').children.push(source)
      end
    end
  end

  # <combinificator:group>!
  #   <combinificator:source url="http://revision3.com/coop/feed/flash-large/" isPrimary="false">!
  #     <combinificator:enclosure url="http://www.podtrac.com/pts/redirect.flv/bitcast-a.bitgravity.com/revision3/flv/coop/0203/coop--0203--cribs01--large.fl8.flv" type="video/x-flv" size="269770468" duration="1744"/>!
  #   </combinfinicator:source>!
  #   <combinificator:source ur578074253l="http://revision3.com/coop/feed/mp4-hd30/" isPrimary="true">!
  #     <combinificator:enclosure url="http://www.podtrac.com/pts/redirect.mp4/bitcast-a.bitgravity.com/revision3/web/coop/0203/coop--0203--cribs01--hd720p30.h264.mp4" type="video/mp4" size="578074253" duration="1744"/>!
  #   </combinificator:source>!
  # </combinificator:group>!



  def to_s
    channel = (self.h % :channel)
    channel.children.each_with_index do |e,i|
      if e.class == Hpricot::Elem && e.name == "item"
        channel.children[i] = Hpricot::XML("")
      end
    end

    @items.each do |item|
      channel.children << item.to_h
    end

    self.h.to_s
  end

end

class FeedFunnel::Feed::Item
  attr_reader :h

  def initialize(h)
    @h = h
    @media = []
    @media_by_url = {}

    self.parse_media
  end

  def enclosure_values
    ((h / :enclosure) + (h / :"media:content")).map do |media|
      {
        :url  => media[:url],
        :size => media[:length] || media[:fileSize],
        :type => media[:type]
      }
    end
  end

  def add_media(media)
    [*media].each do |m|
      @media_by_url[m[:url]] ||= {:count => 0, :media => m}
      @media_by_url[m[:url]][:count] += 1
      @media << m
    end
  end

  def parse_media
    self.add_media(self.enclosure_values)
  end

  def to_h
    self.remove_enclosures
    self.add_media_group
    self.h
  end

  protected

  def remove_enclosures
    idxs = []
    h.children.each_with_index do |e, i|
      if e.class == Hpricot::Elem && e.name =~ /media:content|media:group|enclosure/
        h.children[i] = Hpricot::XML("")
      end
    end
  end

  def add_media_group
    group = (Hpricot::XML("<media:group />") % :"media:group")
    @media_by_url.each do |k, m|
      group.children << media_tag(:"media:content", m[:media])
    end
    h.children << media_tag(:enclosure, @media.first)
    h.children << group
  end

  def media_tag(name, m)
    el = (Hpricot::XML("<#{name} />") % name)
    el[:url]  = m[:url]
    el[:type] = m[:type]
    el[(name.to_s =~ /enclosure/) ? :length : :fileSize] = m[:size]

    el
  end
end

