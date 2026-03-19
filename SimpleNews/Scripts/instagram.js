//
//  instagram.js
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

function isLoginPage() {
  return window.location.pathname.startsWith("/accounts/login")
      || document.querySelector('form[action*="/accounts/login/"]');
}

function isFeedPage() {
  const path = window.location.pathname;
  const isRoot = path === "/" || path === "";
  return isRoot && !isLoginPage();
}

function cleanInstagram() {
  if (!isFeedPage() || isLoginPage()) return;

  const selectors = [
    'section[aria-label="Reels"]',
    'section[aria-label="Suggested for you"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanInstagram();
setInterval(cleanInstagram, 3000);
