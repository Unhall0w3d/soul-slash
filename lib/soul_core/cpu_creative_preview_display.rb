# frozen_string_literal: true
require_relative 'cpu_creative_preview'
module SoulCore
  class CpuCreativePreviewDisplay < CpuCreativePreview
    # Backslash-parentheses/brackets are LibreChat math delimiters. Entities
    # preserve reference text without creating Markdown, HTML or math syntax.
    def self.markdown_data(text)
      entities={'&'=>'&amp;','<'=>'&lt;','>'=>'&gt;','['=>'&#91;',']'=>'&#93;','!'=>'&#33;','*'=>'&#42;','_'=>'&#95;','`'=>'&#96;','\\'=>'&#92;','$'=>'&#36;','#'=>'&#35;','|'=>'&#124;','{'=>'&#123;','}'=>'&#125;'}
      text.gsub(/[&<>\[\]!*_`\\$#|{}]/){|character|entities.fetch(character)}
    end
  end
end
