ext 'apt' do
  if_missing 'apt-get' do
    log "Your system doesn't seem to have Apt installed. Is it Debian-based?"
  end
end

dep 'homebrew' do
  met? {
    if Babushka::BrewHelper.prefix && File.directory?(Babushka::BrewHelper.prefix / 'Library')
      log_ok "homebrew is installed at #{Babushka::BrewHelper.prefix}."
    else
      log_error "no brews."
      :fail
    end
  }
  meet { 
    if_missing 'git' do
      log "Your system doesn't seem to have git installed."
    end
  }
end