vim.ui.select({"red", "green", "blue"}, {}, function (item, idx)
    print(item, idx)
end)

