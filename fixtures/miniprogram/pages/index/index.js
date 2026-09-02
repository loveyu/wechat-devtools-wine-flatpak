Page({
  data: {
    message: "微信开发者工具已成功编译并渲染此页面",
    inputValue: ""
  },
  onInput(event) {
    this.setData({ inputValue: event.detail.value })
  }
})
