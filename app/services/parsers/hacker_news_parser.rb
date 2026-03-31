# frozen_string_literal: true

module Parsers
  # Extracts story listings from Hacker News front page (news.ycombinator.com).
  # Handles the two-row-per-story table layout: .athing (title row) + .subtext (meta row).
  class HackerNewsParser < BaseParser
    HN_ORIGIN = "https://news.ycombinator.com".freeze
    def parse(html)
      document = doc(html)

      {
        stories: extract_stories(document),
        page_metadata: extract_page_metadata(document)
      }
    end

    private

    def extract_stories(document)
      stories = []

      document.css("tr.athing").each do |title_row|
        story = extract_story(title_row)
        next unless story

        stories << story.merge(position: stories.size + 1)
      end

      stories
    end

    def extract_story(title_row)
      title_cell = title_row.at_css("td.title .titleline") || title_row.at_css("td.title")
      return nil unless title_cell

      link = title_cell.at_css("a")
      return nil unless link

      title = text(link)
      url = link["href"]
      url = normalize_hacker_news_url(url)

      site_node = title_cell.at_css("span.sitestr")
      site = text(site_node)

      meta_row = title_row.next_element
      meta = extract_meta(meta_row)

      {
        title: title,
        url: url,
        site: site,
        score: meta[:score],
        author: meta[:author],
        comments_count: meta[:comments_count],
        age: meta[:age],
        hn_id: title_row["id"]
      }
    end

    def normalize_hacker_news_url(href)
      return href if href.blank?
      return href if href.start_with?("http://", "https://")

      "#{HN_ORIGIN}/#{href.delete_prefix("/")}"
    end

    def extract_meta(meta_row)
      result = { score: nil, author: nil, comments_count: nil, age: nil }
      return result unless meta_row

      subtext = meta_row.at_css("td.subtext") || meta_row.at_css("span.subline")
      return result unless subtext

      score_node = subtext.at_css("span.score")
      if score_node
        score_text = text(score_node)
        result[:score] = score_text.to_i if score_text
      end

      author_node = subtext.at_css("a.hnuser")
      result[:author] = text(author_node)

      age_node = subtext.at_css("span.age")
      result[:age] = text(age_node)

      links = subtext.css("a")
      comment_link = links.find { |a| text(a)&.include?("comment") }
      if comment_link
        comment_text = text(comment_link)
        result[:comments_count] = comment_text.to_i if comment_text
      end

      result
    end

    def extract_page_metadata(document)
      more_link = document.at_css("a.morelink")
      { has_more: !more_link.nil? }
    end
  end
end
