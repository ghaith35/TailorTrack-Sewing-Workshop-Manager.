# Sewing Workshop Admin Dashboard

This project is a multi-user management and accounting system designed specifically for a sewing workshop. The application features an Admin Dashboard with a right-to-left layout to support Arabic language users.

## Project Structure

```
sewing_workshop_admin
├── lib
│   ├── main.dart               # Entry point of the application
│   ├── app.dart                # Main application widget
│   ├── l10n
│   │   └── app_ar.arb         # Localization strings for Arabic
│   ├── models
│   │   └── user.dart           # User model definition
│   ├── screens
│   │   ├── dashboard.dart       # Dashboard screen
│   │   ├── users.dart           # Users management screen
│   │   └── accounting.dart      # Accounting functionalities screen
│   ├── widgets
│   │   ├── sidebar.dart         # Sidebar navigation widget
│   │   ├── header.dart          # Header widget with AppBar
│   │   └── user_card.dart       # User card widget
│   └── utils
│       └── responsive.dart      # Responsive design utilities
├── pubspec.yaml                 # Flutter project configuration
└── README.md                    # Project documentation
```

## Features

- **Multi-User Management**: Admins can manage users, including adding, editing, and deleting user accounts.
- **Accounting System**: Track sales and generate reports for better financial management.
- **Responsive Design**: The application adapts to different screen sizes, ensuring a seamless user experience.
- **Arabic Localization**: The application supports Arabic language, providing a right-to-left layout for better accessibility.

## Setup Instructions

1. Clone the repository:
   ```
   git clone <repository-url>
   ```

2. Navigate to the project directory:
   ```
   cd sewing_workshop_admin
   ```

3. Install the dependencies:
   ```
   flutter pub get
   ```

4. Run the application:
   ```
   flutter run
   ```

## Usage Guidelines

- Upon launching the application, users will be greeted with the Admin Dashboard.
- Use the sidebar to navigate between different sections: Dashboard, Users, and Accounting.
- The Dashboard provides quick access to key functionalities, while the Users and Accounting screens allow for detailed management.

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any suggestions or improvements.