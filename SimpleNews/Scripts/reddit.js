//
//  reddit.js
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

function isLoginPage() {
  return window.location.pathname.startsWith("/login");
}

function isFrontPage() {
  const path = window.location.pathname;
  return (path === "/" || path.startsWith("/r/popular")) && !isLoginPage();
}

function cleanReddit() {
  if (!isFrontPage()) return;

  const selectors = [
    'div[data-testid="frontpage-sidebar"]',
    'div[id^="TrendingPosts"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanReddit();
setInterval(cleanReddit, 3000);
