/**
 * Internal dependencies
 */
const { blockNames } = editorPage;
const { toggleDarkMode } = e2eUtils;
import { fetchTheme, takeScreenshotByElement } from './utils';

const quoteBlock = `<!-- wp:quote -->
<blockquote class="wp-block-quote"><!-- wp:paragraph -->
<p>Hello, world!</p>
<!-- /wp:paragraph --><cite>A person</cite></blockquote>
<!-- /wp:quote -->`;

const quoteBlockTwoParagraphs = `<!-- wp:quote -->
<blockquote class="wp-block-quote"><!-- wp:paragraph -->
<p>Praesent eu sollicitudin lorem, ut dignissim lacus. </p>
<!-- /wp:paragraph -->
<!-- wp:paragraph -->
<p>Aliquam pretium, neque et fermentum convallis, dolor eros consequat nisl, quis dignissim magna odio at enim. Nullam vel vulputate mi.&nbsp;</p>
<!-- /wp:paragraph --></blockquote>
<!-- /wp:quote -->`;

describe( 'Gutenberg Editor Visual test for Quote Block', () => {
	it( 'should display correct colors for dark mode', async () => {
		await toggleDarkMode( editorPage.driver, true );
		await editorPage.initializeEditor( {
			initialData: quoteBlock,
		} );

		const block = await editorPage.getBlockAtPosition( blockNames.quote );
		const screenshot = await takeScreenshotByElement( block, {
			padding: 7,
		} );
		await toggleDarkMode( editorPage.driver, false );
		expect( screenshot ).toMatchImageSnapshot();
	} );

	describe( 'For block-based themes', () => {
		let THEME_DATA;

		beforeAll( async () => {
			THEME_DATA = await fetchTheme( { name: 'paimio' } );
		} );

		it( 'should display correct colors with a caption', async () => {
			await editorPage.initializeEditor( {
				initialData: quoteBlock,
				...THEME_DATA,
			} );

			const block = await editorPage.getBlockAtPosition(
				blockNames.quote
			);
			const screenshot = await takeScreenshotByElement( block, {
				padding: 7,
			} );
			expect( screenshot ).toMatchImageSnapshot();
		} );

		it( 'should display correct colors without a caption and two paragraphs', async () => {
			await editorPage.initializeEditor( {
				initialData: quoteBlockTwoParagraphs,
				...THEME_DATA,
			} );

			const block = await editorPage.getBlockAtPosition(
				blockNames.quote
			);
			const screenshot = await takeScreenshotByElement( block, {
				padding: 7,
			} );
			expect( screenshot ).toMatchImageSnapshot();
		} );
	} );
} );
