function readyFn( jQuery ) {

    // Code to run when the document is ready.
    $('#preloader').fadeOut(500);
    $('#main-wrapper').addClass('show');
    
    $("#menu").metisMenu();
    
    $("#checkAll").change(function() {
        $("td input:checkbox").prop('checked', $(this).prop("checked"));
    });

    $(".nav-control").on('click', function() {
        $('#main-wrapper').toggleClass("menu-toggle");
        $(".hamburger").toggleClass("is-active");
    });

    var a_slider = document.getElementById("a_slider");
    slider_setup(a_slider)

    function slider_setup(a_slider) {
        if (!a_slider) {
            return;
        }
        var a_slider_initValue = Number(document.getElementById("a_slider").value);
        var form_trigger_btn = document.getElementById("fund_order_form_trigger");
        var disp_amount = document.getElementById("disp_amount");
        var pos_amount = document.getElementById("pos_amount");
        var neg_amount = document.getElementById("neg_amount");
        var bias = document.getElementById("bias");
        var biasinform = document.getElementById("biasinform");
        var disp_digits = Number(disp_amount.getAttribute("digits"))

        a_slider.oninput = function() {
            function biasValue(cur_value) {
                if (cur_value == a_slider_initValue) {
                    form_trigger_btn.disabled = true;
                    return "";
                } else {
                    form_trigger_btn.disabled = false;

                    if (cur_value < a_slider_initValue) {
                        return "減倉 (-" + (a_slider_initValue - cur_value).toFixed(disp_digits) + ")";
                    } else {
                        return "加倉 (+" + (cur_value - a_slider_initValue).toFixed(disp_digits) + ")";
                    }
                }
            };

            bias.innerHTML = biasValue(parseFloat(this.value));
            biasinform.innerHTML = bias.innerHTML;
            disp_amount.innerHTML = this.value;
            pos_amount.value = this.value;
            neg_amount.value = -this.value;
        }
    };

    var body = $('body');
    var html = $('html');

    "use strict";
    $(function () {
        new quixSettings({
            typography: "roboto",
            version: "light",
            layout: "vertical",
            headerBg: "color_1",
            navheaderBg: "color_1",
            sidebarBg: "color_1",
            sidebarStyle: "full",
            sidebarPosition: "fixed",
            headerPosition: "fixed",
            containerLayout: "wide",
            direction: "ltr"
        });
    });

    //to keep the current page active
    $(function() {
        for (var nk = window.location,
                o = $("ul#menu a").filter(function() {
                    return this.href == nk;
                })
                .addClass("mm-active")
                .parent()
                .addClass("mm-active");;) {
            // console.log(o)
            if (!o.is("li")) break;
            o = o.parent()
                .addClass("mm-show")
                .parent()
                .addClass("mm-active");
        }

        $("ul#menu>li").on('click', function() {
            const sidebarStyle = $('body').attr('data-sidebar-style');
            if (sidebarStyle === 'mini') {
                console.log($(this).find('ul'))
                $(this).find('ul').stop()
            }
        });
    });

    $(function() {
        // var win_w = window.outerWidth;
        var win_h = window.outerHeight;
        var win_h = window.outerHeight;
        if (win_h > 0 ? win_h : screen.height) {
            $(".content-body").css("min-height", (win_h + 60) + "px");
        };
    });

    $('a[data-action="collapse"]').on("click", function(i) {
        i.preventDefault(),
            $(this).closest(".card").find('[data-action="collapse"] i').toggleClass("mdi-arrow-down mdi-arrow-up"),
            $(this).closest(".card").children(".card-body").collapse("toggle");
    });

    $('a[data-action="expand"]').on("click", function(i) {
        i.preventDefault(),
            $(this).closest(".card").find('[data-action="expand"] i').toggleClass("icon-size-actual icon-size-fullscreen"),
            $(this).closest(".card").toggleClass("card-fullscreen");
    });

    $('[data-action="close"]').on("click", function() {
        $(this).closest(".card").removeClass().slideUp("fast");
    });

    $('[data-action="reload"]').on("click", function() {
        var e = $(this);
        e.parents(".card").addClass("card-load"),
            e.parents(".card").append('<div class="card-loader"><i class=" ti-reload rotate-refresh"></div>'),
            setTimeout(function() {
                e.parents(".card").children(".card-loader").remove(),
                    e.parents(".card").removeClass("card-load")
            }, 2000)
    });

    const headerHight = $('.header').innerHeight();

    $(window).scroll(function() {
        if ($('body').attr('data-layout') === "horizontal" && $('body').attr('data-header-position') === "static" && $('body').attr('data-sidebar-position') === "fixed")
            $(this.window).scrollTop() >= headerHight ? $('.quixnav').addClass('fixed') : $('.quixnav').removeClass('fixed')
    });


    function quixSettings({typography, version, layout, navheaderBg, headerBg, sidebarStyle, sidebarBg, sidebarPosition, headerPosition, containerLayout, direction}) {
        this.typography = typography || "roboto";
        this.version = version || "light";
        this.layout = layout || "vertical";
        this.navheaderBg = navheaderBg || "color_1";
        this.headerBg = headerBg || "color_1";
        this.sidebarStyle = sidebarStyle || "full";
        this.sidebarBg = sidebarBg || "color_1";
        this.sidebarPosition = sidebarPosition || "static";
        this.headerPosition = headerPosition || "static";
        this.containerLayout = containerLayout || "wide";
        this.direction = direction || "ltr";

        // this.manageTypography();
        this.manageVersion();
        this.manageLayout();
        this.manageNavHeaderBg();
        this.manageHeaderBg();
        this.manageSidebarStyle();
        this.manageSidebarBg();
        this.manageSidebarPosition();
        this.manageHeaderPosition();
        this.manageContainerLayout();
        this.manageRtlLayout();
        this.manageResponsiveSidebar();
    };

    quixSettings.prototype.manageVersion = function() {
        switch(this.version) {
            case "light": 
                body.attr("data-theme-version", "light");
                break;
            case "dark": 
                body.attr("data-theme-version", "dark");
                break;
            case "transparent": 
                body.attr("data-theme-version", "transparent");
                break;
            default: 
                body.attr("data-theme-version", "light");
        }
    }

    quixSettings.prototype.manageTypography = function() {
        switch(this.version) {
            case "poppins": 
                body.attr("data-typography", "poppins");
                break;
            case "roboto": 
                body.attr("data-typography", "roboto");
                break;
            case "opensans": 
                body.attr("data-typography", "opensans");
                break;
            case "helvetica": 
                body.attr("data-typography", "helvetica");
                break;
            default: 
                body.attr("data-typography", "roboto");
        }
    }

    quixSettings.prototype.manageLayout = function() {
        switch(this.layout) {
            case "horizontal": 
                this.sidebarStyle === "overlay" ? body.attr("data-sidebar-style", "full") : body.attr("data-sidebar-style", `${this.sidebarStyle}`);
                body.attr("data-layout", "horizontal");
                break;
            case "vertical": 
                body.attr("data-layout", "vertical");
                break;
            default:
                body.attr("data-layout", "vertical");
        }
    }

    quixSettings.prototype.manageNavHeaderBg = function() {
        switch(this.navheaderBg) {
            case "color_1": 
                body.attr("data-nav-headerbg", "color_1");
                break;
            case "color_2": 
                body.attr("data-nav-headerbg", "color_2");
                break;
            case "color_3": 
                body.attr("data-nav-headerbg", "color_3");
                break;
            case "color_4": 
                body.attr("data-nav-headerbg", "color_4");
                break;
            case "color_5": 
                body.attr("data-nav-headerbg", "color_5");
                break;
            case "color_6": 
                body.attr("data-nav-headerbg", "color_6");
                break;
            case "color_7": 
                body.attr("data-nav-headerbg", "color_7");
                break;
            case "color_8": 
                body.attr("data-nav-headerbg", "color_8");
                break;
            case "color_9": 
                body.attr("data-nav-headerbg", "color_9");
                break;
            case "color_10": 
                body.attr("data-nav-headerbg", "color_10");
                break;
            case "image_1": 
                body.attr("data-nav-headerbg", "image_1");
                break;
            case "image_2": 
                body.attr("data-nav-headerbg", "image_2");
                break;
            case "image_3": 
                body.attr("data-nav-headerbg", "image_3");
                break;
            default:
                body.attr("data-nav-headerbg", "color_1");
        }
    }

    quixSettings.prototype.manageHeaderBg = function() {
        switch(this.headerBg) {
            case "color_1": 
                body.attr("data-headerbg", "color_1");
                break;
            case "color_2": 
                body.attr("data-headerbg", "color_2");
                break;
            case "color_3": 
                body.attr("data-headerbg", "color_3");
                break;
            case "color_4": 
                body.attr("data-headerbg", "color_4");
                break;
            case "color_5": 
                body.attr("data-headerbg", "color_5");
                break;
            case "color_6": 
                body.attr("data-headerbg", "color_6");
                break;
            case "color_7": 
                body.attr("data-headerbg", "color_7");
                break;
            case "color_8": 
                body.attr("data-headerbg", "color_8");
                break;
            case "color_9": 
                body.attr("data-headerbg", "color_9");
                break;
            case "color_10": 
                body.attr("data-headerbg", "color_10");
                break;
            case "transparent": 
                body.attr("data-headerbg", "transparent");
                break;
            case "gradient_1": 
                body.attr("data-headerbg", "gradient_1");
                break;
            case "gradient_2": 
                body.attr("data-headerbg", "gradient_2");
                break;
            case "gradient_3": 
                body.attr("data-headerbg", "gradient_3");
                break;
            default:
                body.attr("data-headerbg", "color_1");
        }
    }

    quixSettings.prototype.manageSidebarStyle = function() {

        switch(this.sidebarStyle) {
            case "full":
                body.attr("data-sidebar-style", "full");
                break;
            case "mini":
                body.attr("data-sidebar-style", "mini");
                break;
            case "compact":
                body.attr("data-sidebar-style", "compact");
                break;
            case "modern":
                body.attr("data-sidebar-style", "modern");
                break;
            case "icon-hover":
                body.attr("data-sidebar-style", "icon-hover");
        
                $('.quixnav').hover(function() {
                    $('#main-wrapper').addClass('icon-hover-toggle');
                }, function() {
                    $('#main-wrapper').removeClass('icon-hover-toggle');
                });            
                break;
            case "overlay":
                this.layout === "horizontal" ? body.attr("data-sidebar-style", "full") : body.attr("data-sidebar-style", "overlay");
                break;
            default:
                body.attr("data-sidebar-style", "full");
        }
    }

    quixSettings.prototype.manageSidebarBg = function() {
        switch(this.sidebarBg) {
            case "color_1": 
                body.attr("data-sibebarbg", "color_1");
                break;
            case "color_2": 
                body.attr("data-sibebarbg", "color_2");
                break;
            case "color_3": 
                body.attr("data-sibebarbg", "color_3");
                break;
            case "color_4": 
                body.attr("data-sibebarbg", "color_4");
                break;
            case "color_5": 
                body.attr("data-sibebarbg", "color_5");
                break;
            case "color_6": 
                body.attr("data-sibebarbg", "color_6");
                break;
            case "color_7": 
                body.attr("data-sibebarbg", "color_7");
                break;
            case "color_8": 
                body.attr("data-sibebarbg", "color_8");
                break;
            case "color_9": 
                body.attr("data-sibebarbg", "color_9");
                break;
            case "color_10": 
                body.attr("data-sibebarbg", "color_10");
                break;
            case "image_1": 
                body.attr("data-sibebarbg", "image_1");
                break;
            case "image_2": 
                body.attr("data-sibebarbg", "image_2");
                break;
            case "image_3": 
                body.attr("data-sibebarbg", "image_3");
                break;
            default:
                body.attr("data-sibebarbg", "color_1");
        }
    }

    quixSettings.prototype.manageSidebarPosition = function() {
        switch(this.sidebarPosition) {
            case "fixed": 
                this.sidebarStyle === "overlay" && this.layout === "vertical" || this.sidebarStyle === "modern" ? body.attr("data-sidebar-position", "static") : body.attr("data-sidebar-position", "fixed");
                break;
            case "static": 
                body.attr("data-sidebar-position", "static");
                break;
            default: 
                body.attr("data-sidebar-position", "static");       
        }
    }

    quixSettings.prototype.manageHeaderPosition = function() {
        switch(this.headerPosition) {
            case "fixed": 
                body.attr("data-header-position", "fixed");
                break;
            case "static": 
                body.attr("data-header-position", "static");
                break;
            default: 
                body.attr("data-header-position", "static");       
        }
    }

    quixSettings.prototype.manageContainerLayout = function() {
        switch(this.containerLayout) {
            case "boxed":
                if(this.layout === "vertical" && this.sidebarStyle === "full") {
                    body.attr("data-sidebar-style", "overlay");
                }
                body.attr("data-container", "boxed");
                break;
            case "wide":
                body.attr("data-container", "wide");
                break;
            case "wide-boxed": 
                body.attr("data-container", "wide-boxed");
                break;
            default:
                body.attr("data-container", "wide");
        }
    }

    quixSettings.prototype.manageRtlLayout = function() {
        switch(this.direction) {
            case "rtl":
                html.attr("dir", "rtl");
                html.addClass('rtl');
                body.attr("direction", "rtl");
                break;
            case "ltr": 
                html.attr("dir", "ltr");
                html.removeClass('rtl');
                body.attr("direction", "ltr");
                break;
            default: 
                html.attr("dir", "ltr");
                body.attr("direction", "ltr");
        }
    }

    quixSettings.prototype.manageResponsiveSidebar = function() {
        const innerWidth = $(window).innerWidth();
        if(innerWidth < 1200) {
            body.attr("data-layout", "vertical");
            body.attr("data-container", "wide");
        }

        if(innerWidth > 767 && innerWidth < 1200) {
            body.attr("data-sidebar-style", "mini");
        }

        if(innerWidth < 768) {
            body.attr("data-sidebar-style", "overlay");
        }
    }
};

$(window).on("load", readyFn);
$(window).on("turbolinks:load", readyFn);