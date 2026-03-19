//
//  x.js
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

function isLoginPage() {
  return window.location.pathname.startsWith("/login")
      || document.querySelector('form[action="/sessions"]');
}

function isHomeTimeline() {
  const path = window.location.pathname;
  return (path === "/" || path.startsWith("/home")) && !isLoginPage();
}

function cleanX() {
  if (!isHomeTimeline()) return;

  const selectors = [
    'aside[role="complementary"]',
    'div[aria-label="Who to follow"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanX();
setInterval(cleanX, 3000);
