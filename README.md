# PetSpector: System for Determining Pet Breeds Through Image Recognition

It utilizes **Google’s Gemini 2.5 Flash** multimodal AI to identify specific pet breeds and analyze their health sensitivities and behavioral moods through images and video.



## 🌟 Project Overview
Unlike traditional classifiers, PetSpector uses **Large Language Models (LLMs)** to provide contextual health data. The project focuses on five specific pet categories, ensuring highly accurate breed identification and critical safety information regarding allergies.

### Core Capabilities:
* **Breed Identification:** Detects specific breeds for Dogs, Cats, Birds, Saltwater Fish, and Tortoises.
* **Allergy & Health Alerts:** Provides common breed-specific allergies (e.g., skin sensitivities in Bulldogs or Teflon toxicity in Birds).
* **Mood Analysis:** Processes short video clips to interpret pet body language and emotional states.
* **Secure History:** Saves scan history and images using **Firebase Authentication** and **Firebase Storage**.


## 🛠️ Technical Stack
* **Frontend:** [Flutter](https://flutter.dev) (Dart)
* **AI Engine:** [Google Gemini API](https://aistudio.google.com/) (Generative AI)
* **Backend:** [Firebase](https://firebase.google.com/) (Auth, Storage, Firestore)
* **Security:** `flutter_dotenv` for API Key masking.



## ⚙️ Setup & Installation

### 1. Repository Setup
```
git clone https://github.com/jmprz/PetSpector.git
cd petspector
flutter pub get
```

### 2. Secure API Configuration (.env)
This project requires a Gemini API Key. To protect this key from public exposure on GitHub, follow these steps:

In the root directory, create a file named .env:

Paste your API key inside the .env file:

```
GEMINI_API_KEY=your_actual_api_key_here
```

Ensure .env is ignored by Git (Check your .gitignore file for a .env entry).

### 3. Firebase Configuration
Android: Place google-services.json in android/app/.

iOS: Place GoogleService-Info.plist in ios/Runner/.

### 4. Running the Project

```
flutter run
```

## 📋 System Logic & Constraints
The AI model is constrained via System Instruction Prompting:

Strict Filtering: The system rejects non-animal images (e.g., cars, food).

Domain Limitation: If an animal is detected but not in the five supported categories (e.g., a Lion), the system returns a "Not a supported pet" error.

JSON Structuring: All AI responses are forced into a JSON schema to ensure the Flutter UI remains stable and bug-free.


## License
This project is licensed under the [MIT License](LICENSE).
