module Libertree
  module References

    # @param refs [Hash] TODO: explain the refs param, and give an example of it
    def self.replace(text_, refs, server_id, own_pubkey)
      text = text_.dup

      refs.each do |url, segments|
        substitution = segments.entries.reduce(url) do |res, pair|
          segment, ref = pair
          if ref.has_key? 'origin'
            if ref['origin'].to_s == own_pubkey
              local = true
            else
              server = Model::Server[ public_key: ref['origin'].to_s ]
            end
          else
            server = Model::Server[ server_id ]
          end
          next res  if server.nil? && ! local

          if segment =~ /posts/
            model = Model::Post
            target = segment
          else
            model = Model::Comment

            # Look-behind does not support pattern repetition with * or +,
            # so we have to first extract the post id from the url.
            post_id = res.match(%r{/posts/show/(?<post_id>\d+)/})['post_id']
            target = %r{(?<=/posts/show/#{post_id})#{Regexp.quote(segment)}}
          end

          if local
            entities = model.where( id: ref['id'].to_i )
          else
            entities = model.where( remote_id: ref['id'].to_i ).
                       reject {|e| e.member.server != server }
          end

          if entities.empty?
            next res
          else
            updated_segment = segment.gsub(/\d+/, entities[0].id.to_s)
            next res.sub(target, updated_segment)
          end
        end

        if url[/^http/]
          # Chop off everything before /posts/show to turn this into a relative URL.
          new_url = substitution.partition("/posts/").drop(1).join("")
        else
          new_url = substitution
        end

        # only replace full matches
        text.gsub!(%r{#{Regexp.quote(url)}(?!(/|#))}, new_url)
      end

      text
    end

    def self.extract(text, server_name)
      # - match absolute links only if they mention the host of this server
      # - match relative links ("/posts/show/123") when they are beginning the
      #   line (^) or when they are preceded by a space-like character (\s)
      # - capture the matched url
      #
      # Known problems:
      #   - links in verbatim sections are identified, because we extract
      #     references from the raw markdown, not the rendered text.

      pattern = %r{(?<url>(#{server_name}|\s|\()(?<post_url>/posts/show/(?<post_id>\d+))(?<comment_url>/(?<comment_id>\d+)(#comment-\d+)?)?)}

      refs = {}
      text.scan(pattern) do |url, post_url, post_id, comment_url, comment_id|
        next  if post_id.nil?

        post = Libertree::Model::Post[ post_id.to_i ]
        next  if post.nil?

        ref = {}

        map = { 'id' => post.remote_id || post_id.to_i }
        if post.server
          map.merge!( { 'origin' => post.server.public_key } )
        end
        ref[post_url] = map

        comment = Libertree::Model::Comment[ comment_id.to_i ]
        if comment
          map = { 'id' => comment.remote_id || comment_id.to_i }
          if comment.server
            map.merge!({ 'origin' => comment.server.public_key })
          end
          ref[comment_url] = map
        end

        refs[url] = ref  if ref.any?
      end

      refs
    end

  end
end
