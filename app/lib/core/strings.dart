/// All user-facing copy in one place. Plain, direct, factual. No cheerleading.
class S {
  static const app = 'QueueCue';
  static const tagline = 'QueueCue (qq). Because job hunting makes everyone want to cry.';
  static const points = 'Fair Play points';

  // Welcome / onboarding
  static const welcomeTitle = 'Plan the fair. Skip the dead time.';
  static const welcomeBody =
      'See which booths fit you, wait in line from your phone, drop the right resume, and walk up with a pitch that sounds like you.';
  static const startOnboarding = 'Set up in 2 minutes';
  static const demoTitle = 'Demo Mode';
  static const demoBody = 'Pick a seeded student. Everything works without the live model.';
  static const recruiterLogin = 'Recruiter sign-in';
  static const organizer = 'Organizer';
  static const about = 'About';

  static const stepProfile = 'About you';
  static const stepResumes = 'Your resumes';
  static const stepVoice = 'Your voice';
  static const stepBuilding = 'Building your plan';
  static const nameLabel = 'Name';
  static const majorLabel = 'Major';
  static const degreeLabel = 'Degree';
  static const gradYearLabel = 'Graduation year';
  static const emailLabel = 'Email (shared only when a recruiter scans your card)';
  static const workAuthLabel = 'Work authorization';
  static const workAuth = {
    'citizen': 'US citizen',
    'permanent_resident': 'Permanent resident',
    'f1_cpt_opt': 'F-1, needs CPT/OPT',
    'h1b': 'Will need H-1B sponsorship',
  };
  static const workAuthWhy = 'Used only to flag booths that cannot hire you. Never shown to recruiters as a ranking factor.';
  static const avatarLabel = 'Avatar (recruiters see this, not a photo)';
  static const resumesIntro =
      'Upload 2 to 4 versions of your resume, each with a label like "AI/ML" or "Production Eng". QueueCue picks the right one for each booth.';
  static const addPdf = 'Add PDF';
  static const pasteText = 'Paste text instead';
  static const resumeLabelHint = 'Label, e.g. AI/ML';
  static const voicePrompt = "Tell me about a project you're proud of, the way you'd tell a friend.";
  static const voiceWhy =
      '20 to 30 seconds. This is how QueueCue learns how you talk, so your pitch sounds like you and not like a cover letter. Audio is transcribed on the host laptop and then deleted.';
  static const voiceQ1 = 'What kind of work do you want next?';
  static const voiceQ2 = 'How do you explain your work to a non-engineer?';
  static const skipVoice = 'Skip for now';
  static const skipVoiceNote = 'Without your voice, pitches will be plainer and more generic. You can add it later from Me.';
  static const typeInstead = 'Type it instead';
  static const record = 'Record';
  static const stop = 'Stop';

  // Plan
  static const planTitle = 'Your plan';
  static const neverHidden = 'Every booth is listed. Low fits show the reason.';
  static const scanBooth = 'Scan booth QR';
  static const sponsors = 'Sponsors visas';
  static const hiresMajor = 'Hires your major';
  static const citizensOnly = 'US citizens only';
  static const offBeaten = 'Off the beaten booth: high fit, short line';
  static const useResume = 'Use';

  // Booth (student)
  static const joinLine = 'Join line';
  static const dropAndGo = 'Drop and go';
  static const leaveLine = 'Leave line (no points lost)';
  static const scanToJoin = 'Scan the QR code at the booth to join its line.';
  static const pitchBrief = 'Your pitch brief';
  static const moreLikeMe = 'More like me';
  static const shorter = 'Shorter';
  static const differentProject = 'Different project';
  static const edit = 'Edit';
  static const askThis = 'Ask this';
  static const glance = 'Glance at these, do not memorize';
  static const suggestNote = 'Suggest a note in my voice';
  static const notePlaceholder = 'Optional 2-line note to the recruiter';
  static const sendDrop = 'Send to recruiter inbox';
  static const iAskedQuestion = 'I asked my pitch question';
  static const youAreNext = 'You are next';

  // QR
  static const myQrTitle = 'Your card';
  static const myQrBody = 'Show this to the recruiter. It changes every 30 seconds, so a screenshot will not work.';
  static const friendQrBody = 'Let a friend scan this to add each other on the friends leaderboard.';

  // Rolodex
  static const rolodexTitle = 'Rolodex';
  static const rolodexEmpty = 'No one yet. When a recruiter scans your card, they show up here with their contact details.';
  static const addNote = 'Note what you talked about';
  static const recordNote = 'Record 15-second note';
  static const draftEmail = 'Draft follow-up in my voice';
  static const copy = 'Copy';
  static const openMail = 'Open in Mail';
  static const iSentIt = 'I sent it';

  // Game
  static const meTitle = 'Me';
  static const quests = 'Side quests';
  static const badges = 'Badges';
  static const leaderboard = 'Friends leaderboard';
  static const leaderboardOptIn = 'Show me on my friends leaderboard';
  static const pointsNeverRecruiters = 'Points never change what recruiters see or the order they see it in.';
  static const recap = 'Fair Recap';
  static const fairPlay = 'Fair Play matches';
  static const whyHere = 'Why am I here?';
  static const accessHelp = 'Accessibility help';
  static const accessBody = 'Sends your location and what you need to organizer staff. A staff member can also confirm a conversation held at the accessibility desk or by video.';

  // Recruiter
  static const suggestedOrder = 'Suggested order. You decide.';
  static const metSection = 'Met you in person';
  static const waitedSection = 'Waited for you';
  static const sentSection = 'Sent their resume';
  static const strongUnmet = "Strong matches you didn't meet";
  static const met = 'Met';
  static const scanStudent = 'Scan student QR';
  static const groupChat = 'Group chat?';
  static const secondLook = 'Second look';
  static const blindReview = 'Blind review';
  static const closeBooth = "I'm leaving: close my line";
  static const arrivalInfo = 'Arrival time is information only. It is not used to rank.';

  // Generic states
  static const loading = 'Loading';
  static const retry = 'Try again';
  static const offline = 'Live updates paused. Reconnecting.';
}
