//
//  tiktok.js
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

function isLoginPage() {
  const path = window.location.pathname;
  return path.startsWith("/login");
}

function isHomeFeed() {
  const path = window.location.pathname;
  const isRoot = path === "/" || path === "";
  return isRoot && !isLoginPage();
}

function cleanTikTok() {
  if (!isHomeFeed() || isLoginPage()) return;

  const selectors = [
    'div[data-e2e="recommend-side-panel"]',
    'div[data-e2e="trending-hashtag-panel"]',
    'div[data-e2e="footer"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanTikTok();
setInterval(cleanTikTok, 3000);
