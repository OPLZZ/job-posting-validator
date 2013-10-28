var VALIDATOR = {
  empty_value : function ($target, input_id) {
                  return ($target.find(input_id).val() === "");
                }
};

(function($) {
  $(document).ready(function() {
    $("#input-form").bind("submit", function (e) {
      var $target = $(e.target);
      if (!VALIDATOR.empty_value($target, "#url")
          &&
          ($target.find("li.active a").attr("href") === "#tab-url")) {
        $target.attr("method", "GET");
      };
    }); 
  });
})(jQuery);
