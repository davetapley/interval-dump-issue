if ENV['fail'] == 'yes'
  Wodget = Widget.where('1 = ?', 1)
else
  Wodget = Widget.where('1 = 1')
end
