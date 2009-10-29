dep 'new photo entry' do
  requires 'photo blog category dir exists'
  met?{
    file_heading = var(:entry_heading).gsub(/ /,"_")
    filename = var(:blog_date) + "-" + file_heading + ".markdown"
    File.file?( pathify( var(:blog_dir) / "_posts/photo" / filename ))
  }
  meet{
    file_heading = var(:entry_heading).gsub(/ /,"_")
    filename = var(:blog_date) + "-" + file_heading + ".markdown"
    working_dir = pathify( var(:blog_dir) / "_posts/photo" )
    @title = var(:entry_heading)
    in_dir working_dir do
      render_erb "blog/basic_photo.erb", :to => pathify(working_dir / filename)
    end
  }
end

dep 'new blog entry' do
  requires 'blog category dir exists'
  met?{
    file_heading = var(:entry_heading).gsub(/ /,"_")
    filename = var(:blog_date) + "-" + file_heading + ".markdown"
    working_dir = pathify( var(:blog_dir) / "_posts" / var(:blog_category) )
    File.file?( pathify( working_dir / filename))
  }
  meet{
    file_heading = var(:entry_heading).gsub(/ /,"_")
    filename = var(:blog_date) + "-" + file_heading + ".markdown"
    working_dir = pathify( var(:blog_dir) / "_posts" / var(:blog_category) )
    @title = var(:entry_heading)
    in_dir working_dir do
      render_erb "blog/basic_blog.erb", :to => pathify(working_dir / filename)
      shell "mate #{pathify(working_dir / filename)}"
    end
  }
end

dep 'blog category dir exists' do
  met?{ File.directory?(pathify( var(:blog_dir) / "_posts" / var(:blog_category)))}
  meet{
    in_dir var(:blog_dir) do
      dir = "_posts" / var(:blog_category)
      shell "mkdir #{dir}"
    end
  }
end

dep 'photo blog category dir exists' do
  met?{ File.directory?(pathify( var(:blog_dir) / "_posts/photo"))}
  meet{
    in_dir var(:blog_dir) do
      shell "mkdir _posts/photo"
    end
  }
end