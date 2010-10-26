pkg 'apache2 software' do
  installs {
    via :apt, "apache2"
  }
  provides []
end

pkg 'php5 software' do
  installs {
    via :apt, "php5"
  }
  provides []
end

dep "apache with php" do
  requires 'php5 software', 'apache2 software'
end

