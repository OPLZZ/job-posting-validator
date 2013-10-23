(function($) {
  $(document).ready(function() {
    $("#input-form").bind("submit", function (e) {
      var $target = $(e.target);
      if ($target.find("#url").first().val() !== "") {
        $target.attr("method", "GET");
      };
    }); 
  });
})(jQuery);
