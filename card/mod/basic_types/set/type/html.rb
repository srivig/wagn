def clean_html?
  false
end

def diff_args
  { diff_format: :raw }
end

format do
  view :closed_content do |_args|
    ""
  end

  def chunk_list
    :references
  end
end

format :html do
  def editor
    :ace
  end
end
