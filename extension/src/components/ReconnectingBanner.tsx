interface ReconnectingBannerProps {
  visible: boolean;
}

export default function ReconnectingBanner({ visible }: ReconnectingBannerProps) {
  if (!visible) return null;

  return (
    <div className="reconnecting-banner">
      Connection lost. Reconnecting...
    </div>
  );
}
