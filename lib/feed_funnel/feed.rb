require 'hpricot'

module FeedFunnel
  class Feed
    attr_reader :h, :items

    def initialize(rss)
      self.parse(rss)
    end

    def parse(rss)
      @h = Hpricot::XML(rss)
      @items = (h / :item).map {|i| Item.new(i) }
    end

    def to_s
      (self.h / :item).each_with_index do |item, i|
        item.inner_html = @items[i].to_h.inner_html
      end
      self.h.to_s
    end

    class Item
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
        @media.each do |m|
          group.children << media_tag(:"media:content", m)
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
  end
end

