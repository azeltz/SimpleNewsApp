//
//  linkedin.js
//  SimpleNews
//
//  Created by Amir Zeltzer on 3/3/26.
//

function isLoginPage() {
  const path = window.location.pathname;
  return path.startsWith("/login") || path.startsWith("/checkpoint/");
}

function isFeedPage() {
  const path = window.location.pathname;
  return path.startsWith("/feed") && !isLoginPage();
}

function cleanLinkedIn() {
  if (!isFeedPage() || isLoginPage()) return;

  const selectors = [
    'aside[aria-label="LinkedIn News"]',
    'aside[aria-label="Add to your feed"]',
    'section[aria-label="Sponsored"]'
  ];
  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      el.style.display = "none";
    });
  });
}

cleanLinkedIn();
setInterval(cleanLinkedIn, 3000);
