#Wodget = Widget.where('1 = 1')
Wodget = Widget.where('1 = ?', 1)
