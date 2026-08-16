import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
	children: ReactNode;
}

interface State {
	error: Error | null;
}

/**
 * Top-level crash guard. React requires this to be a class component — there
 * is no hook equivalent for getDerivedStateFromError/componentDidCatch.
 * Without this, any uncaught render exception anywhere in the tree unmounts
 * everything to a blank white page.
 */
export class ErrorBoundary extends Component<Props, State> {
	state: State = { error: null };

	static getDerivedStateFromError(error: Error): State {
		return { error };
	}

	componentDidCatch(error: Error, info: ErrorInfo) {
		console.error("Uncaught render error:", error, info.componentStack);
	}

	render() {
		if (this.state.error) {
			return (
				<div className="crash-screen">
					<div className="crash-card">
						<div className="crash-icon">⚠</div>
						<h1>Something went wrong</h1>
						<p>
							ShinyTracker hit an unexpected error and couldn't keep rendering.
							Your hunts are safe — this is a display problem, not a data
							problem.
						</p>
						<pre className="crash-detail">{this.state.error.message}</pre>
						<div className="crash-actions">
							<button
								type="button"
								className="btn gold"
								onClick={() => window.location.reload()}
							>
								Reload
							</button>
							<button
								type="button"
								className="btn ghost"
								onClick={() => this.setState({ error: null })}
							>
								Try again
							</button>
						</div>
					</div>
				</div>
			);
		}

		return this.props.children;
	}
}
