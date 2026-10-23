import { useId } from "react";

function ImageStudy({ id }) {
  return (
    <g>
      <ellipse cx="402" cy="476" rx="174" ry="20" fill="#000" opacity=".45" filter={`url(#${id}-blur)`} />
      <ellipse cx="400" cy="300" rx="279" ry="85" transform="rotate(-29 400 300)" fill="none" stroke="#7489ac" strokeWidth="1" opacity=".35" />
      <ellipse cx="400" cy="300" rx="218" ry="60" transform="rotate(37 400 300)" fill="none" stroke="#bdd1f3" strokeWidth="1" opacity=".24" />
      <circle cx="400" cy="300" r="161" fill={`url(#${id}-glass)`} stroke={`url(#${id}-rim)`} strokeWidth="1.4" />
      <circle cx="400" cy="300" r="151" fill="none" stroke="#dee6f4" opacity=".08" />
      <g clipPath={`url(#${id}-sphere)`}>
        <ellipse cx="464" cy="393" rx="127" ry="87" fill="#a3b5d3" opacity=".17" filter={`url(#${id}-blur)`} />
        <ellipse cx="349" cy="228" rx="72" ry="38" transform="rotate(-39 349 228)" fill="#fff" opacity=".13" filter={`url(#${id}-blur)`} />
        <path d="M260 357C338 220 427 216 552 281" fill="none" stroke="#d1ddf3" strokeWidth="26" opacity=".065" filter={`url(#${id}-blur)`} />
        <path d="M249 354C333 260 431 243 556 278" fill="none" stroke="#dce6f6" strokeWidth="1" opacity=".28" />
        <path d="M264 378C352 271 433 264 546 293" fill="none" stroke="#c9d5e9" strokeWidth=".8" opacity=".12" />
        <ellipse cx="419" cy="332" rx="107" ry="48" transform="rotate(-29 419 332)" fill={`url(#${id}-core)`} />
        <ellipse cx="419" cy="332" rx="107" ry="48" transform="rotate(-29 419 332)" fill="none" stroke="#e1eafa" strokeWidth="1" opacity=".42" />
        <ellipse cx="417" cy="332" rx="78" ry="21" transform="rotate(-29 417 332)" fill="none" stroke="#e4ecfa" opacity=".22" />
        <path d="M292 251A126 126 0 0 1 370 177" fill="none" stroke="#edf2fa" strokeWidth="4" strokeLinecap="round" opacity=".63" />
        <path d="M491 396A139 139 0 0 1 434 437" fill="none" stroke="#bdd1f3" strokeWidth="2" strokeLinecap="round" opacity=".37" />
        <path d="M300 245A130 130 0 0 1 337 200" fill="none" stroke="#fff" strokeWidth="1" opacity=".7" />
      </g>
      <path d="M163 433C233 449 390 413 545 327C602 295 641 264 660 239" fill="none" stroke="#bdd1f3" strokeWidth="1.1" opacity=".58" />
      <circle cx="647" cy="254" r="6" fill="#bdd1f3" />
      <circle cx="206" cy="269" r="3" fill="#f4e6cf" />
      <circle cx="572" cy="407" r="2" fill="#aab6cc" />
      <path d="M606 148v16m-8-8h16M182 371v10m-5-5h10" stroke="#bdd1f3" opacity=".4" />
      <g fill="#94a4bf" fontFamily="monospace" fontSize="10" letterSpacing="2">
        <text x="66" y="520">FORM STUDY / 01</text>
        <text x="655" y="520">LIGHT</text>
      </g>
    </g>
  );
}

function VideoStudy({ id }) {
  return (
    <g>
      <rect x="0" y="0" width="800" height="600" fill={`url(#${id}-sky)`} />
      <ellipse cx="486" cy="280" rx="203" ry="153" fill="#efb67b" opacity=".1" filter={`url(#${id}-blur)`} />
      <circle cx="486" cy="280" r="68" fill={`url(#${id}-sun)`} />
      <path d="M0 377 78 331 135 350 228 265 297 325 355 310 419 348 464 312 536 354 626 278 701 326 800 292V600H0Z" fill="#666357" />
      <path d="m164 325 64-60 47 43-42-21-25 20-17-2Z" fill="#aaa18a" opacity=".45" />
      <path d="m578 319 48-41 49 30-41-16-18 15-14-2Z" fill="#c2ac8b" opacity=".35" />
      <path d="M0 406 88 373 168 392 278 348 366 391 446 367 527 410 654 347 800 389V600H0Z" fill="#323e53" />
      <path d="M0 451 108 415 238 437 354 397 477 430 594 401 711 437 800 417V600H0Z" fill="#242c3b" />
      <path d="M0 486c125-32 219-13 327-24 121-14 235-9 473 40v98H0Z" fill="#181e28" />
      <path d="M0 514c144-21 252 1 353-7 158-12 284 13 447 28v65H0Z" fill="#10151d" />
      <path d="M401 445c58 4 52 17 7 27s-40 15 6 24 33 14 7 23" fill="none" stroke="#d6c39b" strokeWidth="2" opacity=".43" />
      <path d="M47 49h36M47 49v36M753 49h-36M753 49v36M47 551h36M47 551v-36M753 551h-36M753 551v-36" fill="none" stroke="#efeee0" opacity=".39" />
      <g fill="#ece9d9" fontFamily="monospace" fontSize="10" letterSpacing="2">
        <text x="65" y="82">SOMEWHERE, SLOWLY</text>
        <text x="65" y="526">SCENE 001</text>
        <text x="642" y="526">16 : 9</text>
      </g>
      <circle cx="716" cy="78" r="3" fill="#bdd1f3" />
      <rect width="800" height="600" fill={`url(#${id}-vignette)`} />
    </g>
  );
}

function MusicStudy({ id }) {
  return (
    <g>
      <path d="M102 436c73-45 127-30 196-4s150 31 215-6 127-47 192-24" fill="none" stroke="#5c7298" strokeWidth="1" opacity=".24" />
      <rect x="190" y="130" width="334" height="354" rx="3" fill="#000" opacity=".5" transform="rotate(-9 357 307)" filter={`url(#${id}-blur)`} />
      <rect x="173" y="118" width="310" height="350" rx="3" fill="#354258" transform="rotate(-11 328 293)" />
      <rect x="205" y="126" width="310" height="350" rx="3" fill="#5e759c" transform="rotate(-5 360 301)" />
      <circle cx="497" cy="308" r="162" fill={`url(#${id}-record)`} stroke="#38455c" />
      {[145, 139, 130, 124, 115, 108, 99, 92, 84, 76].map((radius) => (
        <circle key={radius} cx="497" cy="308" r={radius} fill="none" stroke="#a6b3c9" strokeWidth=".6" opacity={radius % 2 ? ".13" : ".07"} />
      ))}
      <path d="M379 208A154 154 0 0 1 549 165M590 427a151 151 0 0 1-126 28" fill="none" stroke="#c7d1e1" strokeWidth="7" opacity=".05" />
      <circle cx="497" cy="308" r="48" fill="#aabcdc" />
      <circle cx="497" cy="308" r="40" fill="none" stroke="#2c3648" opacity=".24" />
      <path d="M479 294c15-18 23 29 37 10M479 305c15-18 23 29 37 10" fill="none" stroke="#2f3a4e" strokeWidth="2" />
      <circle cx="497" cy="308" r="5" fill="#0f1319" />
      <rect x="204" y="143" width="282" height="330" rx="2" fill={`url(#${id}-sleeve)`} />
      <rect x="220" y="159" width="250" height="298" fill="none" stroke="#cfd8e7" opacity=".25" />
      <g fill="#1b222d" fontFamily="Georgia, serif" fontSize="45" letterSpacing="-2">
        <text x="235" y="224">STILL IN</text>
        <text x="235" y="268">MOTION.</text>
      </g>
      {[0, 1, 2, 3, 4, 5, 6].map((index) => (
        <path key={index} d={`M230 ${321 + index * 11}c34-55 50 55 86 0s53 56 84 0 42 12 57 0`} fill="none" stroke="#2f3a4e" strokeWidth={index === 3 ? "1.7" : ".9"} opacity={0.65 - index * 0.055} />
      ))}
      <path d="M237 423h61M237 429h34" stroke="#2c374a" opacity=".6" />
      <g fill="#94a4bf" fontFamily="monospace" fontSize="10" letterSpacing="2">
        <text x="66" y="530">SOUND STUDY / 03</text>
        <text x="640" y="530">STEREO</text>
      </g>
    </g>
  );
}

/** Decorative, locally drawn concept artwork; never represents a generated asset. */
export default function StudioArt({ kind = "image", className = "" }) {
  const id = `studio-art-${useId().replace(/:/g, "")}`;
  const Study = { image: ImageStudy, video: VideoStudy, music: MusicStudy }[kind] || ImageStudy;

  return (
    <svg className={className} viewBox="0 0 800 600" width="100%" height="100%" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
      <defs>
        <radialGradient id={`${id}-background`} cx="47%" cy="43%" r="65%">
          <stop offset="0" stopColor="#1e2633" />
          <stop offset=".62" stopColor="#12161e" />
          <stop offset="1" stopColor="#0e1116" />
        </radialGradient>
        <radialGradient id={`${id}-glass`} cx="31%" cy="22%" r="84%">
          <stop offset="0" stopColor="#d0daeb" stopOpacity=".27" />
          <stop offset=".3" stopColor="#8597b6" stopOpacity=".07" />
          <stop offset=".68" stopColor="#0b0f16" stopOpacity=".34" />
          <stop offset=".91" stopColor="#6d83a8" stopOpacity=".18" />
          <stop offset="1" stopColor="#d5e1f5" stopOpacity=".35" />
        </radialGradient>
        <linearGradient id={`${id}-rim`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#e8edf6" stopOpacity=".85" />
          <stop offset=".45" stopColor="#687ea5" stopOpacity=".08" />
          <stop offset="1" stopColor="#bfd0ec" stopOpacity=".55" />
        </linearGradient>
        <radialGradient id={`${id}-core`}>
          <stop stopColor="#c5d7f5" stopOpacity=".42" />
          <stop offset=".57" stopColor="#91a8cf" stopOpacity=".17" />
          <stop offset="1" stopColor="#bdd1f3" stopOpacity=".02" />
        </radialGradient>
        <linearGradient id={`${id}-sky`} x2="0" y2="1">
          <stop stopColor="#1e2531" />
          <stop offset=".43" stopColor="#8b826b" />
          <stop offset=".72" stopColor="#d1a780" />
          <stop offset="1" stopColor="#465775" />
        </linearGradient>
        <linearGradient id={`${id}-sun`} x2="0" y2="1">
          <stop stopColor="#f5d9ac" />
          <stop offset="1" stopColor="#dfa77b" />
        </linearGradient>
        <radialGradient id={`${id}-vignette`}>
          <stop offset=".45" stopColor="#0d1117" stopOpacity="0" />
          <stop offset="1" stopColor="#0d1117" stopOpacity=".38" />
        </radialGradient>
        <linearGradient id={`${id}-record`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#0e1116" />
          <stop offset=".36" stopColor="#202835" />
          <stop offset=".52" stopColor="#0e1218" />
          <stop offset=".78" stopColor="#1e2633" />
          <stop offset="1" stopColor="#0d1016" />
        </linearGradient>
        <linearGradient id={`${id}-sleeve`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#c9d5eb" />
          <stop offset="1" stopColor="#90a0bd" />
        </linearGradient>
        <filter id={`${id}-blur`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="15" />
        </filter>
        <clipPath id={`${id}-sphere`}><circle cx="400" cy="300" r="160" /></clipPath>
      </defs>
      <rect width="800" height="600" fill={`url(#${id}-background)`} />
      <Study id={id} />
    </svg>
  );
}
